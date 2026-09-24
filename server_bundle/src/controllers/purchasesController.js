const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ─── TRANSACTIONS (PURCHASES & SELLS WITH MULTIPLE ITEMS & CATEGORY) ────
exports.getTransactions = (req, res) => {
  try {
    const transactions = db.prepare(`
      SELECT * FROM purchase_sell_transactions 
      ORDER BY transaction_date DESC, created_at DESC
    `).all();
    
    // Parse items_json back to JS array for the response
    const formatted = transactions.map(t => ({
      ...t,
      items: JSON.parse(t.items_json)
    }));
    
    res.json(formatted);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createTransaction = (req, res) => {
  // Use a database transaction to ensure purchase log and stock updates happen atomically
  const dbTransaction = db.transaction((data) => {
    const { receipt_no, type, category, transaction_date, contact_person, remarks, items } = data;
    
    let totalBillAmount = 0.0;
    const itemsWithTotals = [];
    const transId = uuidv4();

    // 1. Process items and calculate totals
    for (const item of items) {
      const { item_name, quantity, unit, price_per_unit } = item;
      const qty = parseFloat(quantity);
      const price = parseFloat(price_per_unit);
      
      const itemTotal = qty * price;
      totalBillAmount += itemTotal;

      itemsWithTotals.push({
        item_name,
        quantity: qty,
        unit,
        price_per_unit: price,
        total_price: itemTotal,
        cost_price_per_unit: item.cost_price_per_unit !== undefined ? parseFloat(item.cost_price_per_unit) : undefined,
        cost_total_price: item.cost_total_price !== undefined ? parseFloat(item.cost_total_price) : undefined,
        profit_loss: item.profit_loss !== undefined ? parseFloat(item.profit_loss) : undefined
      });

      // 2. Integration with Kitchen/General Stock
      const isRation = category && category.toLowerCase() === 'ration';
      
      if (isRation) {
        let stockItem = db.prepare('SELECT * FROM kitchen_stock WHERE LOWER(item_name) = ?').get(item_name.toLowerCase());
        if (!stockItem) {
          const newStockId = uuidv4();
          db.prepare('INSERT INTO kitchen_stock (id, item_name, quantity, unit, min_threshold) VALUES (?, ?, ?, ?, ?)')
            .run(newStockId, item_name, 0.0, unit, 5.0);
          stockItem = { id: newStockId, item_name, quantity: 0.0, unit };
        }
        
        let newQty = stockItem.quantity;
        if (type === 'Purchase') {
          newQty += qty;
        } else if (type === 'Sell' || type === 'Issue' || type === 'Use') {
          newQty -= qty;
          if (newQty < 0) {
            throw new Error(`Insufficient kitchen stock for ${item_name}. Available quantity is ${stockItem.quantity} ${stockItem.unit}.`);
          }
        }
        
        db.prepare('UPDATE kitchen_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stockItem.id);
        
        const logId = uuidv4();
        db.prepare(`
          INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks)
          VALUES (?, ?, ?, ?, ?, ?)
        `).run(
          logId, 
          stockItem.id, 
          type === 'Purchase' ? 'In' : 'Out', 
          qty, 
          stockItem.unit, 
          `Linked to Invoice/Bill No: ${receipt_no} (#${transId}): ${remarks || ''}`
        );
      } else {
        let stockItem = db.prepare('SELECT * FROM general_stock WHERE LOWER(item_name) = ?').get(item_name.toLowerCase());
        if (!stockItem) {
          const newStockId = uuidv4();
          db.prepare('INSERT INTO general_stock (id, item_name, quantity, unit, category, min_threshold) VALUES (?, ?, ?, ?, ?, ?)')
            .run(newStockId, item_name, 0.0, unit, category || 'General', 5.0);
          stockItem = { id: newStockId, item_name, quantity: 0.0, unit, category: category || 'General' };
        } else {
          db.prepare('UPDATE general_stock SET category = ?, updated_at = datetime(\'now\') WHERE id = ?').run(category || 'General', stockItem.id);
        }
        
        let newQty = stockItem.quantity;
        if (type === 'Purchase') {
          newQty += qty;
        } else if (type === 'Sell' || type === 'Issue' || type === 'Use') {
          newQty -= qty;
          if (newQty < 0) {
            throw new Error(`Insufficient general stock for ${item_name}. Available quantity is ${stockItem.quantity} ${stockItem.unit}.`);
          }
        }
        
        db.prepare('UPDATE general_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stockItem.id);
        
        const logId = uuidv4();
        db.prepare(`
          INSERT INTO general_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(
          logId, 
          stockItem.id, 
          type === 'Purchase' ? 'In' : 'Out', 
          qty, 
          stockItem.unit, 
          `Linked to Invoice/Bill No: ${receipt_no} (#${transId}): ${remarks || ''}`,
          transaction_date
        );
      }
    }

    // 3. Log the Parent Purchase/Sell transaction with items_json
    const itemsJsonStr = JSON.stringify(itemsWithTotals);
    db.prepare(`
      INSERT INTO purchase_sell_transactions (id, receipt_no, type, category, transaction_date, contact_person, total_price, remarks, items_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(transId, receipt_no, type, category || 'Other', transaction_date, contact_person || null, totalBillAmount, remarks || null, itemsJsonStr);

    return { id: transId, receipt_no, type, category: category || 'Other', transaction_date, contact_person, total_price: totalBillAmount, remarks, items: itemsWithTotals };
  });

  try {
    const { receipt_no, type, transaction_date, items } = req.body;
    if (!receipt_no || !type || !transaction_date || !items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'receipt_no, type, transaction_date, and a non-empty items array are required' });
    }

    if (type !== 'Purchase' && type !== 'Sell' && type !== 'Issue' && type !== 'Use') {
      return res.status(400).json({ error: 'type must be Purchase, Sell, Issue, or Use' });
    }

    // Validate each item
    for (const item of items) {
      if (!item.item_name || !item.quantity || !item.unit || item.price_per_unit === undefined) {
        return res.status(400).json({ error: 'Each item must have item_name, quantity, unit, and price_per_unit' });
      }
      const qty = parseFloat(item.quantity);
      const price = parseFloat(item.price_per_unit);
      if (isNaN(qty) || qty <= 0) {
        return res.status(400).json({ error: 'Quantity must be a positive number' });
      }
      if (isNaN(price) || price < 0) {
        return res.status(400).json({ error: 'Price per unit must be a non-negative number' });
      }
    }

    const result = dbTransaction(req.body);
    res.status(201).json(result);
  } catch (error) {
    console.error('Error creating transaction:', error);
    res.status(400).json({ error: error.message });
  }
};

exports.updateTransaction = (req, res) => {
  const dbTransaction = db.transaction((data) => {
    const { id, receipt_no, type, category, transaction_date, contact_person, remarks, items } = data;
    
    // 1. Fetch existing transaction
    const existing = db.prepare('SELECT * FROM purchase_sell_transactions WHERE id = ?').get(id);
    if (!existing) {
      throw new Error('Transaction not found');
    }

    const oldItems = JSON.parse(existing.items_json);

    // 2. Reverse Old Stock Integration
    const isOldRation = existing.category && existing.category.toLowerCase() === 'ration';
    for (const oldItem of oldItems) {
      if (isOldRation) {
        const stockItem = db.prepare('SELECT * FROM kitchen_stock WHERE LOWER(TRIM(item_name)) = LOWER(TRIM(?))').get(oldItem.item_name);
        if (stockItem) {
          let reversedQty = stockItem.quantity;
          if (existing.type === 'Purchase') {
            reversedQty -= oldItem.quantity;
          } else if (existing.type === 'Sell' || existing.type === 'Issue' || existing.type === 'Use') {
            reversedQty += oldItem.quantity;
          }
          db.prepare('UPDATE kitchen_stock SET quantity = ? WHERE id = ?').run(reversedQty, stockItem.id);
        }
      } else {
        const stockItem = db.prepare('SELECT * FROM general_stock WHERE LOWER(TRIM(item_name)) = LOWER(TRIM(?))').get(oldItem.item_name);
        if (stockItem) {
          let reversedQty = stockItem.quantity;
          if (existing.type === 'Purchase') {
            reversedQty -= oldItem.quantity;
          } else if (existing.type === 'Sell' || existing.type === 'Issue' || existing.type === 'Use') {
            reversedQty += oldItem.quantity;
          }
          db.prepare('UPDATE general_stock SET quantity = ? WHERE id = ?').run(reversedQty, stockItem.id);
        }
      }
    }

    // 3. Process New Items and calculate new total price
    let totalBillAmount = 0.0;
    const itemsWithTotals = [];

    for (const item of items) {
      const { item_name, quantity, unit, price_per_unit } = item;
      const qty = parseFloat(quantity);
      const price = parseFloat(price_per_unit);
      
      const itemTotal = qty * price;
      totalBillAmount += itemTotal;

      itemsWithTotals.push({
        item_name,
        quantity: qty,
        unit,
        price_per_unit: price,
        total_price: itemTotal,
        cost_price_per_unit: item.cost_price_per_unit !== undefined ? parseFloat(item.cost_price_per_unit) : undefined,
        cost_total_price: item.cost_total_price !== undefined ? parseFloat(item.cost_total_price) : undefined,
        profit_loss: item.profit_loss !== undefined ? parseFloat(item.profit_loss) : undefined
      });

      // 4. Update Stock with New Quantities
      const isRation = category && category.toLowerCase() === 'ration';
      
      if (isRation) {
        let stockItem = db.prepare('SELECT * FROM kitchen_stock WHERE LOWER(item_name) = ?').get(item_name.toLowerCase());
        if (!stockItem) {
          const newStockId = uuidv4();
          db.prepare('INSERT INTO kitchen_stock (id, item_name, quantity, unit, min_threshold) VALUES (?, ?, ?, ?, ?)')
            .run(newStockId, item_name, 0.0, unit, 5.0);
          stockItem = { id: newStockId, item_name, quantity: 0.0, unit };
        }
        
        let newQty = stockItem.quantity;
        if (type === 'Purchase') {
          newQty += qty;
        } else if (type === 'Sell' || type === 'Issue' || type === 'Use') {
          newQty -= qty;
          if (newQty < 0) {
            throw new Error(`Insufficient kitchen stock for ${item_name}. Available quantity after reversal is ${stockItem.quantity} ${stockItem.unit}.`);
          }
        }
        
        db.prepare('UPDATE kitchen_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stockItem.id);
        
        const logId = uuidv4();
        db.prepare(`
          INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks)
          VALUES (?, ?, ?, ?, ?, ?)
        `).run(
          logId, 
          stockItem.id, 
          type === 'Purchase' ? 'In' : 'Out', 
          qty, 
          stockItem.unit, 
          `Updated via Bill/Invoice No: ${receipt_no} (#${id}): ${remarks || ''}`
        );
      } else {
        let stockItem = db.prepare('SELECT * FROM general_stock WHERE LOWER(item_name) = ?').get(item_name.toLowerCase());
        if (!stockItem) {
          const newStockId = uuidv4();
          db.prepare('INSERT INTO general_stock (id, item_name, quantity, unit, category, min_threshold) VALUES (?, ?, ?, ?, ?, ?)')
            .run(newStockId, item_name, 0.0, unit, category || 'General', 5.0);
          stockItem = { id: newStockId, item_name, quantity: 0.0, unit, category: category || 'General' };
        } else {
          db.prepare('UPDATE general_stock SET category = ?, updated_at = datetime(\'now\') WHERE id = ?').run(category || 'General', stockItem.id);
        }
        
        let newQty = stockItem.quantity;
        if (type === 'Purchase') {
          newQty += qty;
        } else if (type === 'Sell' || type === 'Issue' || type === 'Use') {
          newQty -= qty;
          if (newQty < 0) {
            throw new Error(`Insufficient general stock for ${item_name}. Available quantity after reversal is ${stockItem.quantity} ${stockItem.unit}.`);
          }
        }
        
        db.prepare('UPDATE general_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stockItem.id);
        
        const logId = uuidv4();
        db.prepare(`
          INSERT INTO general_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(
          logId, 
          stockItem.id, 
          type === 'Purchase' ? 'In' : 'Out', 
          qty, 
          stockItem.unit, 
          `Updated via Bill/Invoice No: ${receipt_no} (#${id}): ${remarks || ''}`,
          transaction_date
        );
      }
    }

    // 5. Update the Parent Transaction
    const itemsJsonStr = JSON.stringify(itemsWithTotals);
    db.prepare(`
      UPDATE purchase_sell_transactions 
      SET receipt_no = ?, type = ?, category = ?, transaction_date = ?, contact_person = ?, total_price = ?, remarks = ?, items_json = ?
      WHERE id = ?
    `).run(receipt_no, type, category || 'Other', transaction_date, contact_person || null, totalBillAmount, remarks || null, itemsJsonStr, id);

    return { id, receipt_no, type, category: category || 'Other', transaction_date, contact_person, total_price: totalBillAmount, remarks, items: itemsWithTotals };
  });

  try {
    const { id } = req.params;
    const { receipt_no, type, category, transaction_date, contact_person, remarks, items } = req.body;
    if (!receipt_no || !type || !transaction_date || !items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'receipt_no, type, transaction_date, and a non-empty items array are required' });
    }

    if (type !== 'Purchase' && type !== 'Sell') {
      return res.status(400).json({ error: 'type must be either Purchase or Sell' });
    }

    // Validate each item
    for (const item of items) {
      if (!item.item_name || !item.quantity || !item.unit || item.price_per_unit === undefined) {
        return res.status(400).json({ error: 'Each item must have item_name, quantity, unit, and price_per_unit' });
      }
      const qty = parseFloat(item.quantity);
      const price = parseFloat(item.price_per_unit);
      if (isNaN(qty) || qty <= 0) {
        return res.status(400).json({ error: 'Quantity must be a positive number' });
      }
      if (isNaN(price) || price < 0) {
        return res.status(400).json({ error: 'Price per unit must be a non-negative number' });
      }
    }

    const result = dbTransaction({ id, receipt_no, type, category, transaction_date, contact_person, remarks, items });
    res.json(result);
  } catch (error) {
    console.error('Error updating transaction:', error);
    res.status(400).json({ error: error.message });
  }
};

exports.deleteTransaction = (req, res) => {
  const dbTransaction = db.transaction((data) => {
    const { id, itemName } = data;
    const existing = db.prepare('SELECT * FROM purchase_sell_transactions WHERE id = ?').get(id);
    if (!existing) {
      throw new Error('Transaction not found');
    }

    const items = JSON.parse(existing.items_json);
    const isRation = existing.category && existing.category.toLowerCase() === 'ration';

    let itemsToDelete = [];
    let itemsToKeep = [];

    if (itemName) {
      const trimmedTarget = itemName.trim().toLowerCase();
      for (const item of items) {
        const name = (item.item_name || item.itemName || '').trim().toLowerCase();
        if (name === trimmedTarget) {
          itemsToDelete.push(item);
        } else {
          itemsToKeep.push(item);
        }
      }
      if (itemsToDelete.length === 0) {
        itemsToDelete = items;
        itemsToKeep = [];
      }
    } else {
      itemsToDelete = items;
      itemsToKeep = [];
    }

    for (const item of itemsToDelete) {
      const name = item.item_name || item.itemName;
      if (!name) continue;

      if (isRation) {
        const kitchenStockItem = db.prepare('SELECT * FROM kitchen_stock WHERE LOWER(TRIM(item_name)) = LOWER(TRIM(?))').get(name);
        if (kitchenStockItem) {
          let reversedQty = kitchenStockItem.quantity;
          if (existing.type.toLowerCase() === 'purchase') {
            reversedQty -= item.quantity;
            if (reversedQty < 0) {
              throw new Error(`Cannot delete this item. Reversing it would make kitchen stock negative for ${name} (Current: ${kitchenStockItem.quantity} ${kitchenStockItem.unit}).`);
            }
          } else if (existing.type.toLowerCase() === 'sell' || existing.type.toLowerCase() === 'issue' || existing.type.toLowerCase() === 'use') {
            reversedQty += item.quantity;
          }

          db.prepare("UPDATE kitchen_stock SET quantity = ?, updated_at = datetime('now') WHERE id = ?").run(reversedQty, kitchenStockItem.id);

          const logId = uuidv4();
          db.prepare(`
            INSERT INTO kitchen_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks)
            VALUES (?, ?, ?, ?, ?, ?)
          `).run(
            logId, 
            kitchenStockItem.id, 
            existing.type.toLowerCase() === 'purchase' ? 'Out' : 'In', 
            item.quantity, 
            kitchenStockItem.unit, 
            `Reversal due to deletion of item "${name}" from Bill No: ${existing.receipt_no} (#${id})`
          );
        }
      } else {
        const generalStockItem = db.prepare('SELECT * FROM general_stock WHERE LOWER(TRIM(item_name)) = LOWER(TRIM(?))').get(name);
        if (generalStockItem) {
          let reversedQty = generalStockItem.quantity;
          if (existing.type.toLowerCase() === 'purchase') {
            reversedQty -= item.quantity;
            if (reversedQty < 0) {
              throw new Error(`Cannot delete this item. Reversing it would make general stock negative for ${name} (Current: ${generalStockItem.quantity} ${generalStockItem.unit}).`);
            }
          } else if (existing.type.toLowerCase() === 'sell' || existing.type.toLowerCase() === 'issue' || existing.type.toLowerCase() === 'use') {
            reversedQty += item.quantity;
          }

          db.prepare("UPDATE general_stock SET quantity = ?, updated_at = datetime('now') WHERE id = ?").run(reversedQty, generalStockItem.id);

          const logId = uuidv4();
          db.prepare(`
            INSERT INTO general_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          `).run(
            logId, 
            generalStockItem.id, 
            existing.type.toLowerCase() === 'purchase' ? 'Out' : 'In', 
            item.quantity, 
            generalStockItem.unit, 
            `Reversal due to deletion of item "${name}" from Bill No: ${existing.receipt_no} (#${id})`,
            existing.transaction_date
          );
        }
      }
    }

    if (itemsToKeep.length > 0) {
      const newTotalPrice = itemsToKeep.reduce((sum, item) => sum + (parseFloat(item.quantity) * parseFloat(item.price_per_unit || item.pricePerUnit || 0.0)), 0.0);
      db.prepare('UPDATE purchase_sell_transactions SET items_json = ?, total_price = ? WHERE id = ?')
        .run(JSON.stringify(itemsToKeep), newTotalPrice, id);
      return { deletedEntire: false };
    } else {
      db.prepare('DELETE FROM purchase_sell_transactions WHERE id = ?').run(id);
      return { deletedEntire: true };
    }
  });

  try {
    const { id } = req.params;
    const { itemName } = req.query;
    const result = dbTransaction({ id, itemName });
    res.json({ message: 'Transaction deleted successfully', ...result });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

// ─── UNIT OPTIONS MANAGEMENT ──────────────────────────────────────────
exports.getUnits = (req, res) => {
  try {
    const units = db.prepare('SELECT * FROM units ORDER BY name').all();
    res.json(units);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createUnit = (req, res) => {
  try {
    const { name } = req.body;
    if (!name || name.trim() === '') {
      return res.status(400).json({ error: 'Unit name is required' });
    }

    const id = uuidv4();
    const cleanName = name.trim().toLowerCase();

    db.prepare('INSERT INTO units (id, name) VALUES (?, ?)').run(id, cleanName);
    res.status(201).json({ id, name: cleanName });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Unit already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.deleteUnit = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM units WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Unit not found' });
    }
    res.json({ message: 'Unit deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── CATEGORY OPTIONS MANAGEMENT ──────────────────────────────────────
exports.getCategories = (req, res) => {
  try {
    const categories = db.prepare('SELECT * FROM purchase_categories ORDER BY name').all();
    res.json(categories);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createCategory = (req, res) => {
  try {
    const { name } = req.body;
    if (!name || name.trim() === '') {
      return res.status(400).json({ error: 'Category name is required' });
    }

    const id = uuidv4();
    const cleanName = name.trim(); // preserve capitalization for nice UI look

    db.prepare('INSERT INTO purchase_categories (id, name) VALUES (?, ?)').run(id, cleanName);
    res.status(201).json({ id, name: cleanName });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Category already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.deleteCategory = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM purchase_categories WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Category not found' });
    }
    res.json({ message: 'Category deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.getGeneralStock = (req, res) => {
  try {
    const stock = db.prepare('SELECT * FROM general_stock ORDER BY item_name').all();
    
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
          // Ignore
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

exports.issueGeneralStock = (req, res) => {
  const dbTransaction = db.transaction((data) => {
    const { receipt_no, transaction_date, category, contact_person, remarks, items } = data;
    const transId = uuidv4();

    let totalIssueValue = 0.0;
    const itemsWithTotals = [];

    for (const item of items) {
      const { stock_id, quantity } = item;
      const qty = parseFloat(quantity);
      if (isNaN(qty) || qty <= 0) {
        throw new Error('Quantity must be a positive number');
      }

      // Fetch stock item
      const stockItem = db.prepare('SELECT * FROM general_stock WHERE id = ?').get(stock_id);
      if (!stockItem) {
        throw new Error('Stock item not found');
      }

      if (stockItem.quantity < qty) {
        throw new Error(`Insufficient stock for ${stockItem.item_name}. Available: ${stockItem.quantity} ${stockItem.unit}, required: ${qty} ${stockItem.unit}.`);
      }

      // Deduct stock
      const newQty = stockItem.quantity - qty;
      db.prepare('UPDATE general_stock SET quantity = ?, updated_at = datetime(\'now\') WHERE id = ?').run(newQty, stockItem.id);

      // Record stock transaction log
      const logId = uuidv4();
      db.prepare(`
        INSERT INTO general_stock_transactions (id, stock_id, transaction_type, quantity, unit, remarks, transaction_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(
        logId, 
        stockItem.id, 
        'Out', 
        qty, 
        stockItem.unit, 
        `Issued / Marked In Use: ${remarks || ''}`,
        transaction_date
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
          const match = tItems.find(i => i.item_name.toLowerCase().trim() === stockItem.item_name.toLowerCase().trim());
          if (match) {
            latestPrice = parseFloat(match.price_per_unit || (match.quantity > 0 ? (match.total_price / match.quantity) : 0.0));
            break;
          }
        } catch (e) {
          // Ignore
        }
      }

      const itemTotal = qty * latestPrice;
      totalIssueValue += itemTotal;

      itemsWithTotals.push({
        item_name: stockItem.item_name,
        quantity: qty,
        unit: stockItem.unit,
        price_per_unit: latestPrice,
        total_price: itemTotal
      });
    }

    // Record Issue transaction parent record
    const itemsJsonStr = JSON.stringify(itemsWithTotals);
    db.prepare(`
      INSERT INTO purchase_sell_transactions (id, receipt_no, type, category, transaction_date, contact_person, total_price, remarks, items_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(transId, receipt_no, 'Issue', category || 'Other', transaction_date, contact_person || null, totalIssueValue, remarks || null, itemsJsonStr);

    return { 
      id: transId, 
      receipt_no, 
      type: 'Issue', 
      category: category || 'Other', 
      transaction_date, 
      contact_person, 
      total_price: totalIssueValue, 
      remarks, 
      items: itemsWithTotals 
    };
  });

  try {
    const { receipt_no, transaction_date, items } = req.body;
    if (!receipt_no || !transaction_date || !items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'receipt_no, transaction_date, and a non-empty items array are required' });
    }

    const result = dbTransaction(req.body);
    res.status(201).json(result);
  } catch (error) {
    console.error('Error logging issue/consumption:', error);
    res.status(400).json({ error: error.message });
  }
};

exports.updateGeneralStockItem = (req, res) => {
  try {
    const { id } = req.params;
    const { item_name, min_threshold, quantity, unit, category } = req.body;

    const existing = db.prepare('SELECT * FROM general_stock WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'General stock item not found' });
    }

    db.prepare(`
      UPDATE general_stock 
      SET item_name = ?, min_threshold = ?, quantity = ?, unit = ?, category = ?, updated_at = datetime('now') 
      WHERE id = ?
    `).run(
      item_name || existing.item_name,
      min_threshold !== undefined ? min_threshold : existing.min_threshold,
      quantity !== undefined ? quantity : existing.quantity,
      unit || existing.unit,
      category || existing.category,
      id
    );

    res.json({ message: 'General stock item updated successfully', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteGeneralStockItem = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM general_stock WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'General stock item not found' });
    }
    res.json({ message: 'General stock item deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
