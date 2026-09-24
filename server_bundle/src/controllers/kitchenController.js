const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ─── DAILY FOOD MENU ───────────────────────────────────────────────
exports.getMenu = (req, res) => {
  try {
    const menu = db.prepare('SELECT * FROM kitchen_menu ORDER BY day_of_week, meal_type').all();
    res.json(menu);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.updateMenuItem = (req, res) => {
  try {
    const { day_of_week, meal_type, items, notes } = req.body;
    if (!day_of_week || !meal_type || items === undefined) {
      return res.status(400).json({ error: 'day_of_week, meal_type, and items are required' });
    }

    // Check if entry exists
    const existing = db.prepare('SELECT id FROM kitchen_menu WHERE day_of_week = ? AND meal_type = ?').get(day_of_week, meal_type);

    if (existing) {
      db.prepare(`
        UPDATE kitchen_menu 
        SET items = ?, notes = ?, updated_at = datetime('now') 
        WHERE day_of_week = ? AND meal_type = ?
      `).run(items, notes || null, day_of_week, meal_type);
      res.json({ message: 'Menu updated successfully', day_of_week, meal_type, items, notes });
    } else {
      const id = uuidv4();
      db.prepare(`
        INSERT INTO kitchen_menu (id, day_of_week, meal_type, items, notes) 
        VALUES (?, ?, ?, ?, ?)
      `).run(id, day_of_week, meal_type, items, notes || null);
      res.status(201).json({ id, day_of_week, meal_type, items, notes });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteMenuItem = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM kitchen_menu WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Menu item not found' });
    }
    res.json({ message: 'Menu item deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── RATION STOCK ──────────────────────────────────────────────────
exports.getStock = (req, res) => {
  try {
    const stock = db.prepare('SELECT * FROM kitchen_stock ORDER BY item_name').all();
    
    // For each item, find its latest purchase unit price to estimate total value
    const transactions = db.prepare(`
      SELECT items_json FROM purchase_sell_transactions 
      WHERE type = 'Purchase' 
      ORDER BY transaction_date DESC, created_at DESC
    `).all();

    const stockWithValues = stock.map(item => {
      let latestPrice = 0.0;
      for (const t of transactions) {
        try {
          if (!t.items_json) continue;
          const items = JSON.parse(t.items_json);
          const match = items.find(i => i.item_name.toLowerCase().trim() === item.item_name.toLowerCase().trim());
          if (match) {
            latestPrice = parseFloat(match.price_per_unit || (match.quantity > 0 ? (match.total_price / match.quantity) : 0.0));
            break;
          }
        } catch (e) {
          // Ignore parse errors
        }
      }

      const totalAmount = item.quantity * latestPrice;
      return {
        ...item,
        latest_price: latestPrice,
        total_amount: totalAmount
      };
    });

    res.json(stockWithValues);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createStockItem = (req, res) => {
  try {
    const { item_name, quantity, unit, min_threshold } = req.body;
    if (!item_name || unit === undefined) {
      return res.status(400).json({ error: 'item_name and unit are required' });
    }

    const id = uuidv4();
    const qty = quantity || 0;
    const threshold = min_threshold || 0;

    db.prepare(`
      INSERT INTO kitchen_stock (id, item_name, quantity, unit, min_threshold) 
      VALUES (?, ?, ?, ?, ?)
    `).run(id, item_name, qty, unit, threshold);

    res.status(201).json({ id, item_name, quantity: qty, unit, min_threshold: threshold });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Stock item with this name already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateStockItem = (req, res) => {
  try {
    const { id } = req.params;
    const { item_name, min_threshold, quantity, unit } = req.body;

    const existing = db.prepare('SELECT * FROM kitchen_stock WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Stock item not found' });
    }

    db.prepare(`
      UPDATE kitchen_stock 
      SET item_name = ?, min_threshold = ?, quantity = ?, unit = ?, updated_at = datetime('now') 
      WHERE id = ?
    `).run(
      item_name || existing.item_name,
      min_threshold !== undefined ? min_threshold : existing.min_threshold,
      quantity !== undefined ? quantity : existing.quantity,
      unit || existing.unit,
      id
    );

    res.json({ message: 'Stock item updated successfully', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteStockItem = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM kitchen_stock WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Stock item not found' });
    }
    res.json({ message: 'Stock item deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── STOCK TRANSACTIONS ────────────────────────────────────────────
exports.getStockTransactions = (req, res) => {
  try {
    const transactions = db.prepare(`
      SELECT t.*, s.item_name as item_name, s.unit as stock_unit 
      FROM kitchen_stock_transactions t
      JOIN kitchen_stock s ON t.stock_id = s.id
      ORDER BY t.transaction_date DESC, t.created_at DESC
    `).all();
    res.json(transactions);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.recordStockTransaction = (req, res) => {
  const transaction = db.transaction((transaction_type, quantity, remarks, stock_id) => {
    // 1. Fetch current stock item
    const stock = db.prepare('SELECT * FROM kitchen_stock WHERE id = ?').get(stock_id);
    if (!stock) {
      throw new Error('Stock item not found');
    }

    // 2. Compute new quantity
    let newQty = stock.quantity;
    if (transaction_type === 'In') {
      newQty += quantity;
    } else if (transaction_type === 'Out') {
      newQty -= quantity;
      if (newQty < 0) {
        throw new Error(`Insufficient stock. Current quantity is ${stock.quantity} ${stock.unit}.`);
      }
    } else {
      throw new Error('Invalid transaction type. Must be In or Out.');
    }

    // 3. Update kitchen_stock
    db.prepare("UPDATE kitchen_stock SET quantity = ?, updated_at = datetime('now') WHERE id = ?").run(newQty, stock_id);

    // 4. Record transaction log
    const transId = uuidv4();
    db.prepare(`
      INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(transId, stock_id, transaction_type, quantity, stock.unit, remarks || null);

    return { transId, stock_id, transaction_type, quantity, unit: stock.unit, remarks, newQuantity: newQty };
  });

  try {
    const { stock_id, transaction_type, quantity, remarks } = req.body;
    if (!stock_id || !transaction_type || !quantity) {
      return res.status(400).json({ error: 'stock_id, transaction_type, and quantity are required' });
    }

    if (quantity <= 0) {
      return res.status(400).json({ error: 'Quantity must be greater than zero' });
    }

    const result = transaction(transaction_type, parseFloat(quantity), remarks, stock_id);
    res.status(201).json(result);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

// ─── EXPENSES ──────────────────────────────────────────────────────
exports.getExpenses = (req, res) => {
  try {
    const expenses = db.prepare('SELECT * FROM kitchen_expenses ORDER BY expense_date DESC, created_at DESC').all();
    res.json(expenses);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createExpense = (req, res) => {
  try {
    const { item_name, amount, expense_date, remarks } = req.body;
    if (!item_name || !amount || !expense_date) {
      return res.status(400).json({ error: 'item_name, amount, and expense_date are required' });
    }

    const id = uuidv4();
    db.prepare(`
      INSERT INTO kitchen_expenses (id, item_name, amount, expense_date, remarks) 
      VALUES (?, ?, ?, ?, ?)
    `).run(id, item_name, parseFloat(amount), expense_date, remarks || null);

    res.status(201).json({ id, item_name, amount, expense_date, remarks });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteExpense = (req, res) => {
  const dbTransaction = db.transaction((params) => {
    const { id, itemName } = params;
    const existing = db.prepare('SELECT * FROM kitchen_expenses WHERE id = ?').get(id);
    if (!existing) {
      throw new Error('Expense record not found');
    }

    const remarks = existing.remarks || '';
    if (remarks.startsWith('Consumed:')) {
      const splitOnRemarks = remarks.split(/\.\s*Remarks:/);
      const consumedSection = splitOnRemarks[0];
      const userRemarks = splitOnRemarks[1] ? splitOnRemarks[1].trim() : '';
      const itemsListStr = consumedSection.replace(/^Consumed:\s*/, '').trim();

      // Remove trailing period if present
      const cleanStr = itemsListStr.endsWith('.') ? itemsListStr.slice(0, -1) : itemsListStr;
      const parts = cleanStr.split(',').map(s => s.trim()).filter(Boolean);

      const parsedItems = [];
      for (const part of parts) {
        const match = part.match(/^(.+?)\s*\(\s*([\d.]+)\s*([a-zA-Z\s]+)\s*-\s*cost\s*₹\s*([\d.]+)\s*\)$/i);
        if (match) {
          parsedItems.push({
            rawText: part,
            name: match[1].trim(),
            qty: parseFloat(match[2]),
            unit: match[3].trim(),
            cost: parseFloat(match[4])
          });
        }
      }

      if (itemName) {
        // Delete only the FIRST matching item
        const matchIndex = parsedItems.findIndex(item => item.name.toLowerCase() === itemName.toLowerCase());
        if (matchIndex !== -1) {
          const itemToDelete = parsedItems[matchIndex];
          parsedItems.splice(matchIndex, 1);

          // Revert stock for this single item
          const stockItem = db.prepare('SELECT * FROM kitchen_stock WHERE LOWER(TRIM(item_name)) = LOWER(TRIM(?))').get(itemToDelete.name);
          if (stockItem) {
            const newQty = stockItem.quantity + itemToDelete.qty;
            db.prepare("UPDATE kitchen_stock SET quantity = ?, updated_at = datetime('now') WHERE id = ?").run(newQty, stockItem.id);

            const transLogId = uuidv4();
            db.prepare(`
              INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
              VALUES (?, ?, ?, ?, ?, ?, ?)
            `).run(
              transLogId, 
              stockItem.id, 
              'In', 
              itemToDelete.qty, 
              stockItem.unit, 
              `Reversal of item [${itemToDelete.name}] from Kitchen Expense (${existing.item_name})`,
              existing.expense_date
            );
          }

          if (parsedItems.length > 0) {
            // Update the existing expense
            const newRemarks = `Consumed: ${parsedItems.map(i => `${i.name} (${i.qty} ${i.unit} - cost ₹${i.cost})`).join(', ')}.${userRemarks ? ` Remarks: ${userRemarks}` : ''}`;
            const newAmount = parsedItems.reduce((sum, item) => sum + item.cost, 0);

            db.prepare('UPDATE kitchen_expenses SET remarks = ?, amount = ? WHERE id = ?').run(newRemarks, newAmount, id);
            return { deletedEntire: false };
          }
        }
      } else {
        // Revert stock for ALL items
        for (const item of parsedItems) {
          const stockItem = db.prepare('SELECT * FROM kitchen_stock WHERE LOWER(TRIM(item_name)) = LOWER(TRIM(?))').get(item.name);
          if (stockItem) {
            const newQty = stockItem.quantity + item.qty;
            db.prepare("UPDATE kitchen_stock SET quantity = ?, updated_at = datetime('now') WHERE id = ?").run(newQty, stockItem.id);

            const transLogId = uuidv4();
            db.prepare(`
              INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
              VALUES (?, ?, ?, ?, ?, ?, ?)
            `).run(
              transLogId, 
              stockItem.id, 
              'In', 
              item.qty, 
              stockItem.unit, 
              `Reversal due to deletion of Kitchen Expense (${existing.item_name})`,
              existing.expense_date
            );
          }
        }
      }
    }

    // Delete the entire expense entry
    db.prepare('DELETE FROM kitchen_expenses WHERE id = ?').run(id);
    return { deletedEntire: true };
  });

  try {
    const { id } = req.params;
    const { itemName } = req.query;
    const result = dbTransaction({ id, itemName });
    res.json({ message: 'Expense deleted successfully', ...result });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

// ─── MEAL PLANNING ─────────────────────────────────────────────────
exports.getMealPlans = (req, res) => {
  try {
    const plans = db.prepare('SELECT * FROM kitchen_meal_plans ORDER BY plan_date DESC').all();
    res.json(plans);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createMealPlan = (req, res) => {
  try {
    const { plan_date, meal_type, menu_items, expected_count } = req.body;
    if (!plan_date || !meal_type || !menu_items) {
      return res.status(400).json({ error: 'plan_date, meal_type, and menu_items are required' });
    }

    const id = uuidv4();
    const count = expected_count || 0;

    db.prepare(`
      INSERT INTO kitchen_meal_plans (id, plan_date, meal_type, menu_items, expected_count, status) 
      VALUES (?, ?, ?, ?, ?, 'Planned')
    `).run(id, plan_date, meal_type, menu_items, count);

    res.status(201).json({ id, plan_date, meal_type, menu_items, expected_count: count, status: 'Planned' });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'A meal plan already exists for this date and meal type' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateMealPlan = (req, res) => {
  try {
    const { id } = req.params;
    const { status, menu_items, expected_count } = req.body;

    const existing = db.prepare('SELECT * FROM kitchen_meal_plans WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Meal plan not found' });
    }

    db.prepare(`
      UPDATE kitchen_meal_plans 
      SET status = ?, menu_items = ?, expected_count = ? 
      WHERE id = ?
    `).run(
      status || existing.status,
      menu_items || existing.menu_items,
      expected_count !== undefined ? expected_count : existing.expected_count,
      id
    );

    res.json({ message: 'Meal plan updated successfully', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteMealPlan = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM kitchen_meal_plans WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Meal plan not found' });
    }
    res.json({ message: 'Meal plan deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.issueMealRation = (req, res) => {
  const dbTransaction = db.transaction((data) => {
    const { meal_name, issue_date, items, remarks } = data;
    
    let totalMealCost = 0.0;
    const itemsDescription = [];

    // Process each ration item
    for (const item of items) {
      const { stock_id, quantity, estimated_cost } = item;
      const qty = parseFloat(quantity);
      const cost = parseFloat(estimated_cost || 0.0);
      
      totalMealCost += cost;

      // 1. Fetch current stock item
      const stock = db.prepare('SELECT * FROM kitchen_stock WHERE id = ?').get(stock_id);
      if (!stock) {
        throw new Error(`Stock item not found for ID: ${stock_id}`);
      }

      // 2. Deduct quantity
      const newQty = stock.quantity - qty;
      if (newQty < 0) {
        throw new Error(`Insufficient stock for ${stock.item_name}. Available quantity is ${stock.quantity} ${stock.unit}, but tried to issue ${qty} ${stock.unit}.`);
      }

      // 3. Update stock quantity
      db.prepare('UPDATE kitchen_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stock.id);

      // 4. Record stock transaction log
      const transLogId = uuidv4();
      db.prepare(`
        INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(
        transLogId, 
        stock.id, 
        'Out', 
        qty, 
        stock.unit, 
        `Issued for Meal: ${meal_name}. ${remarks || ''}`,
        issue_date
      );

      itemsDescription.push(`${stock.item_name} (${qty} ${stock.unit} - cost ₹${cost})`);
    }

    // 5. Log the overall meal consumption as a kitchen expense
    const expenseId = uuidv4();
    const expenseTitle = `Meal Issue: ${meal_name}`;
    const itemizedDetails = `Consumed: ${itemsDescription.join(', ')}. Remarks: ${remarks || ''}`;

    db.prepare(`
      INSERT INTO kitchen_expenses (id, item_name, amount, expense_date, remarks)
      VALUES (?, ?, ?, ?, ?)
    `).run(expenseId, expenseTitle, totalMealCost, issue_date, itemizedDetails);

    return { 
      success: true, 
      expenseId, 
      meal_name, 
      total_cost: totalMealCost, 
      issue_date 
    };
  });

  try {
    const { meal_name, issue_date, items } = req.body;
    if (!meal_name || !issue_date || !items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'meal_name, issue_date, and a non-empty items array are required' });
    }

    // Validate each item
    for (const item of items) {
      if (!item.stock_id || item.quantity === undefined) {
        return res.status(400).json({ error: 'Each item must have stock_id and quantity' });
      }
      const qty = parseFloat(item.quantity);
      if (isNaN(qty) || qty <= 0) {
        return res.status(400).json({ error: 'Quantity must be a positive number' });
      }
      if (item.estimated_cost !== undefined) {
        const cost = parseFloat(item.estimated_cost);
        if (isNaN(cost) || cost < 0) {
          return res.status(400).json({ error: 'Estimated cost must be a non-negative number' });
        }
      }
    }

    const result = dbTransaction(req.body);
    res.status(201).json(result);
  } catch (error) {
    console.error('Error issuing meal ration:', error);
    res.status(400).json({ error: error.message });
  }
};

exports.issueTodayMenuRation = (req, res) => {
  const dbTransaction = db.transaction((data) => {
    const { day_of_week, issue_date, remarks } = data;
    
    // 1. Fetch menu items for this day
    const meals = db.prepare('SELECT * FROM kitchen_menu WHERE LOWER(day_of_week) = ?').all(day_of_week.toLowerCase());
    
    if (meals.length === 0) {
      throw new Error(`No daily food menu items defined for ${day_of_week}.`);
    }

    let totalExpense = 0.0;
    const itemsDescription = [];
    const issuedIngredients = [];

    // 2. Loop through each meal type
    for (const meal of meals) {
      let itemsList = [];
      try {
        if (meal.items.startsWith('[')) {
          itemsList = JSON.parse(meal.items);
        }
      } catch (e) {
        continue;
      }

      for (const menuItem of itemsList) {
        if (!menuItem.ingredients || !Array.isArray(menuItem.ingredients)) continue;

        for (const ing of menuItem.ingredients) {
          const { stock_id, quantity } = ing;
          const qty = parseFloat(quantity);
          if (isNaN(qty) || qty <= 0) continue;

          // Fetch stock item
          const stock = db.prepare('SELECT * FROM kitchen_stock WHERE id = ?').get(stock_id);
          if (!stock) {
            throw new Error(`Stock item not found for ingredient: ${ing.item_name || stock_id}`);
          }

          // Check and deduct quantity
          const newQty = stock.quantity - qty;
          if (newQty < 0) {
            throw new Error(`Insufficient stock for ${stock.item_name} in ${meal.meal_type} menu. Available: ${stock.quantity} ${stock.unit}, required: ${qty} ${stock.unit}.`);
          }

          // Update database
          db.prepare('UPDATE kitchen_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stock.id);

          // Record transaction log
          const transLogId = uuidv4();
          db.prepare(`
            INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          `).run(
            transLogId,
            stock.id,
            'Out',
            qty,
            stock.unit,
            `Auto-issued for Menu Meal (${day_of_week} - ${meal.meal_type}).`,
            issue_date
          );

          // Lookup latest purchase price to calculate cost
          const latestPurchase = db.prepare(`
            SELECT items_json FROM purchase_sell_transactions 
            WHERE type = 'Purchase' 
            ORDER BY transaction_date DESC, created_at DESC
          `).all();

          let latestPrice = 0.0;
          for (const t of latestPurchase) {
            try {
              if (!t.items_json) continue;
              const tItems = JSON.parse(t.items_json);
              const match = tItems.find(i => i.item_name.toLowerCase().trim() === stock.item_name.toLowerCase().trim());
              if (match) {
                latestPrice = parseFloat(match.price_per_unit || 0.0);
                break;
              }
            } catch (e) {
              // Ignore
            }
          }

          const cost = qty * latestPrice;
          totalExpense += cost;
          itemsDescription.push(`${stock.item_name} (${qty} ${stock.unit} - cost ₹${cost})`);
          
          issuedIngredients.push({
            stock_id: stock.id,
            item_name: stock.item_name,
            quantity: qty,
            unit: stock.unit,
            latest_price: latestPrice,
            cost: cost
          });
        }
      }
    }

    if (issuedIngredients.length === 0) {
      throw new Error(`No sub-item ingredients defined in today's menu meals.`);
    }

    // 3. Log overall menu issue as a kitchen expense
    const expenseId = uuidv4();
    const expenseTitle = `Daily Menu Issue: ${day_of_week}`;
    const itemizedDetails = `Consumed: ${itemsDescription.join(', ')}. ${remarks || ''}`;

    db.prepare(`
      INSERT INTO kitchen_expenses (id, item_name, amount, expense_date, remarks)
      VALUES (?, ?, ?, ?, ?)
    `).run(expenseId, expenseTitle, totalExpense, issue_date, itemizedDetails);

    return {
      success: true,
      expenseId,
      day_of_week,
      issue_date,
      total_cost: totalExpense,
      ingredients: issuedIngredients
    };
  });

  try {
    const { day_of_week, issue_date, remarks } = req.body;
    if (!day_of_week || !issue_date) {
      return res.status(400).json({ error: 'day_of_week and issue_date are required' });
    }

    const result = dbTransaction(req.body);
    res.status(201).json(result);
  } catch (error) {
    console.error('Error issuing daily menu ration:', error);
    res.status(400).json({ error: error.message });
  }
};
