import 'dart:math';
import 'seating_models.dart';

class SeatingAlgorithm {
  final Random _random = Random();

  SeatingResult generate({
    required int hallRows,
    required int hallColumns,
    required List<StudentSeatInput> students,
    required List<SeatHistoryEntry> seatHistory,
    required int hallId,
    List<List<SeatAssignment?>>? initialGrid,
  }) {
    final totalSeats = hallRows * hallColumns;
    final warnings = <String>[];

    // Initialize grid from initialGrid if provided, else empty grid
    final grid = List<List<SeatAssignment?>>.generate(
      hallRows,
      (r) => List.generate(
        hallColumns,
        (c) => (initialGrid != null && r < initialGrid.length && c < initialGrid[r].length)
            ? initialGrid[r][c]
            : null,
      ),
    );

    if (students.isEmpty) {
      final existingAssignments = <SeatAssignment>[];
      for (int r = 0; r < hallRows; r++) {
        for (int c = 0; c < hallColumns; c++) {
          if (grid[r][c] != null) existingAssignments.add(grid[r][c]!);
        }
      }
      return SeatingResult(
        assignments: existingAssignments,
        primaryMethod: 'NONE',
        totalStudents: existingAssignments.length,
        placedCount: existingAssignments.length,
        warnings: existingAssignments.isEmpty ? ['No students to place.'] : [],
      );
    }

    // Group students by bookName or bookId
    final bookGroups = <String, List<StudentSeatInput>>{};
    for (final s in students) {
      final key = s.bookName.trim().isNotEmpty ? s.bookName.trim() : (s.bookId.trim().isNotEmpty ? s.bookId.trim() : s.className);
      bookGroups.putIfAbsent(key, () => []).add(s);
    }

    int getRollNum(StudentSeatInput s) {
      if (s.rollNumber != null && s.rollNumber!.trim().isNotEmpty) {
        final p = int.tryParse(s.rollNumber!.replaceAll(RegExp(r'\D'), ''));
        if (p != null) return p;
      }
      if (s.registrationNumber.trim().isNotEmpty) {
        final p = int.tryParse(s.registrationNumber.replaceAll(RegExp(r'\D'), ''));
        if (p != null) return p;
      }
      return 999999;
    }

    // Sort students by Roll Number and apply Front-Back Interleaving
    // (Roll 1, Roll N, Roll 2, Roll N-1...) so Roll 1 sits next to the LAST Roll Number!
    for (final entry in bookGroups.entries) {
      final list = entry.value;
      list.sort((a, b) => getRollNum(a).compareTo(getRollNum(b)));
      final interleaved = <StudentSeatInput>[];
      int l = 0;
      int r = list.length - 1;
      while (l <= r) {
        if (l == r) {
          interleaved.add(list[l]);
          break;
        }
        interleaved.add(list[l]);
        interleaved.add(list[r]);
        l++;
        r--;
      }
      bookGroups[entry.key] = interleaved;
    }

    // Single-book edge case
    if (bookGroups.length == 1) {
      warnings.add(
          'Only 1 subject/book found. Anti-adjacency not applicable. Using history-aware random placement.');
      return _singleBookPlacement(
          hallRows, hallColumns, students, seatHistory, hallId, warnings, grid);
    }

    if (students.length > totalSeats) {
      warnings.add(
          'WARNING: ${students.length} students but only $totalSeats seats. ${students.length - totalSeats} will overflow.');
    }

    // ── Tier 1: Anti-Adjacency Interleaving ─────────────────────
    final tier1Result =
        _tier1AntiAdjacency(grid, hallRows, hallColumns, bookGroups, seatHistory, hallId);
    final unplacedAfterT1 = tier1Result.unplaced;
    final t1Count = tier1Result.placedCount;

    if (unplacedAfterT1.isEmpty) {
      return _buildResult(grid, hallRows, hallColumns, [], warnings,
          'ANTI_ADJACENCY', students.length, t1Count, 0, 0);
    }

    warnings.add(
        '${unplacedAfterT1.length} students could not be placed with strict anti-adjacency. Applying merit-based redistribution.');

    // ── Tier 2: Merit-Based Spread ──────────────────────────────
    final tier2Result = _tier2MeritSpread(grid, hallRows, hallColumns, unplacedAfterT1);
    final unplacedAfterT2 = tier2Result.unplaced;
    final t2Count = tier2Result.placedCount;

    if (unplacedAfterT2.isEmpty) {
      return _buildResult(grid, hallRows, hallColumns, [], warnings,
          'MERIT_SPREAD', students.length, t1Count, t2Count, 0);
    }

    warnings.add(
        '${unplacedAfterT2.length} students still unplaced. Applying random fail-safe assignment.');

    // ── Tier 3: Random Fail-Safe ────────────────────────────────
    final tier3Result = _tier3Random(grid, hallRows, hallColumns, unplacedAfterT2);
    final overflow = tier3Result.overflow;
    final t3Count = tier3Result.placedCount;

    if (overflow.isNotEmpty) {
      warnings.add(
          'CRITICAL: ${overflow.length} students cannot fit. Add more halls or increase capacity.');
    }

    return _buildResult(grid, hallRows, hallColumns, overflow, warnings,
        'RANDOM', students.length, t1Count, t2Count, t3Count);
  }

  // ── Tier 1: Anti-Adjacency ──────────────────────────────────────

  _TierResult _tier1AntiAdjacency(
    List<List<SeatAssignment?>> grid,
    int rows,
    int cols,
    Map<String, List<StudentSeatInput>> bookGroups,
    List<SeatHistoryEntry> history,
    int hallId,
  ) {
    // Sort groups by size descending — place the largest groups first
    final sortedBookIds = bookGroups.keys.toList()
      ..sort((a, b) => bookGroups[b]!.length.compareTo(bookGroups[a]!.length));

    // Shuffle students within each group
    for (final bookId in sortedBookIds) {
      bookGroups[bookId]!.shuffle(_random);
    }

    // Build queues
    final queues = <String, List<StudentSeatInput>>{};
    for (final bookId in sortedBookIds) {
      queues[bookId] = List.from(bookGroups[bookId]!);
    }

    // Build history lookup: "studentId:bookId:hallId:row:col" -> true
    final historySet = <String>{};
    for (final h in history) {
      historySet.add('${h.studentId}:${h.bookId}:${h.hallId}:${h.seatRow}:${h.seatColumn}');
    }

    int placedCount = 0;
    int bookCycleIndex = 0;

    for (int r = 0; r < rows; r++) {
      // Shift starting book for each row to create checkerboard effect
      final rowStartIndex = (bookCycleIndex + r) % sortedBookIds.length;

      for (int c = 0; c < cols; c++) {
        if (grid[r][c] != null) continue; // Skip pre-occupied seats
        final targetBookIndex = (rowStartIndex + c) % sortedBookIds.length;
        bool placed = false;

        // Try each book starting from the target
        for (int attempt = 0; attempt < sortedBookIds.length; attempt++) {
          final tryIndex = (targetBookIndex + attempt) % sortedBookIds.length;
          final bookId = sortedBookIds[tryIndex];
          final queue = queues[bookId]!;

          if (queue.isEmpty) continue;

          // Try to find a student that passes adjacency + history check
          for (int si = 0; si < queue.length; si++) {
            final student = queue[si];

            if (!_isValidPlacement(grid, r, c, rows, cols, student.bookId)) {
              continue;
            }

            final historyKey = '${student.studentId}:${student.bookId}:$hallId:$r:$c';
            if (historySet.contains(historyKey)) {
              // Try another student from same book queue
              continue;
            }

            // Place the student
            grid[r][c] = SeatAssignment(
              student: student,
              seat: SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1),
              method: 'ANTI_ADJACENCY',
            );
            queue.removeAt(si);
            placedCount++;
            placed = true;
            break;
          }

          if (placed) break;
        }

        // If still not placed, try any student that passes adjacency (ignore history)
        if (!placed) {
          for (final bookId in sortedBookIds) {
            final queue = queues[bookId]!;
            for (int si = 0; si < queue.length; si++) {
              if (_isValidPlacement(grid, r, c, rows, cols, queue[si].bookId)) {
                grid[r][c] = SeatAssignment(
                  student: queue[si],
                  seat: SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1),
                  method: 'ANTI_ADJACENCY',
                );
                queue.removeAt(si);
                placedCount++;
                placed = true;
                break;
              }
            }
            if (placed) break;
          }
        }
      }
    }

    // Collect unplaced
    final unplaced = <StudentSeatInput>[];
    for (final queue in queues.values) {
      unplaced.addAll(queue);
    }

    return _TierResult(placedCount: placedCount, unplaced: unplaced);
  }

  bool _isValidPlacement(
      List<List<SeatAssignment?>> grid, int row, int col, int rows, int cols, String bookId) {
    // Check 4-directional adjacency
    const directions = [
      [-1, 0], // top
      [1, 0], // bottom
      [0, -1], // left
      [0, 1], // right
    ];

    for (final d in directions) {
      final nr = row + d[0];
      final nc = col + d[1];
      if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
        final neighbor = grid[nr][nc];
        if (neighbor != null && neighbor.student.bookId == bookId) {
          return false;
        }
      }
    }
    return true;
  }

  // ── Tier 2: Merit-Based Spread ──────────────────────────────────

  _TierResult _tier2MeritSpread(
    List<List<SeatAssignment?>> grid,
    int rows,
    int cols,
    List<StudentSeatInput> unplaced,
  ) {
    // Sort by merit descending (high scorers first)
    final sorted = List<StudentSeatInput>.from(unplaced)
      ..sort((a, b) => (b.meritScore ?? 0).compareTo(a.meritScore ?? 0));

    final emptySeats = <SeatPosition>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] == null) {
          emptySeats.add(SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1));
        }
      }
    }

    int placedCount = 0;
    final stillUnplaced = <StudentSeatInput>[];

    // Separate top 25% high scorers for spatial spreading
    final highScorerCount = (sorted.length * 0.25).ceil().clamp(1, sorted.length);
    final highScorers = sorted.sublist(0, highScorerCount);
    final remaining = sorted.sublist(highScorerCount);

    // Place high scorers with max-distance strategy
    for (final student in highScorers) {
      if (emptySeats.isEmpty) {
        stillUnplaced.add(student);
        continue;
      }

      SeatPosition? bestSeat;
      int bestMinDist = -1;

      for (final seat in emptySeats) {
        final minDist =
            _minDistanceToSameBook(grid, rows, cols, seat.row, seat.col, student.bookId);
        if (minDist > bestMinDist) {
          bestMinDist = minDist;
          bestSeat = seat;
        }
      }

      if (bestSeat != null) {
        grid[bestSeat.row][bestSeat.col] = SeatAssignment(
          student: student,
          seat: bestSeat,
          method: 'MERIT_SPREAD',
        );
        emptySeats.remove(bestSeat);
        placedCount++;
      } else {
        stillUnplaced.add(student);
      }
    }

    // Place remaining — try anti-adjacency first, relax if needed
    for (final student in remaining) {
      if (emptySeats.isEmpty) {
        stillUnplaced.add(student);
        continue;
      }

      // First pass: strict anti-adjacency
      SeatPosition? chosenSeat;
      for (final seat in emptySeats) {
        if (_isValidPlacement(grid, seat.row, seat.col, rows, cols, student.bookId)) {
          chosenSeat = seat;
          break;
        }
      }

      // Second pass: relaxed (any empty seat with max distance)
      chosenSeat ??= _findMaxDistanceSeat(grid, rows, cols, emptySeats, student.bookId);

      if (chosenSeat != null) {
        grid[chosenSeat.row][chosenSeat.col] = SeatAssignment(
          student: student,
          seat: chosenSeat,
          method: 'MERIT_SPREAD',
        );
        emptySeats.remove(chosenSeat);
        placedCount++;
      } else {
        stillUnplaced.add(student);
      }
    }

    return _TierResult(placedCount: placedCount, unplaced: stillUnplaced);
  }

  int _minDistanceToSameBook(
      List<List<SeatAssignment?>> grid, int rows, int cols, int row, int col, String bookId) {
    int minDist = rows + cols; // max possible manhattan distance
    bool found = false;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final a = grid[r][c];
        if (a != null && a.student.bookId == bookId) {
          final dist = (row - r).abs() + (col - c).abs();
          if (dist < minDist) {
            minDist = dist;
            found = true;
          }
        }
      }
    }
    return found ? minDist : rows + cols;
  }

  SeatPosition? _findMaxDistanceSeat(List<List<SeatAssignment?>> grid, int rows, int cols,
      List<SeatPosition> emptySeats, String bookId) {
    if (emptySeats.isEmpty) return null;

    SeatPosition? best;
    int bestDist = -1;
    for (final seat in emptySeats) {
      final dist = _minDistanceToSameBook(grid, rows, cols, seat.row, seat.col, bookId);
      if (dist > bestDist) {
        bestDist = dist;
        best = seat;
      }
    }
    return best;
  }

  // ── Tier 3: Random Fail-Safe ────────────────────────────────────

  _Tier3Result _tier3Random(
    List<List<SeatAssignment?>> grid,
    int rows,
    int cols,
    List<StudentSeatInput> unplaced,
  ) {
    final emptySeats = <SeatPosition>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] == null) {
          emptySeats.add(SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1));
        }
      }
    }
    emptySeats.shuffle(_random);

    int placedCount = 0;
    final overflow = <StudentSeatInput>[];
    int seatIdx = 0;

    for (final student in unplaced) {
      if (seatIdx < emptySeats.length) {
        final seat = emptySeats[seatIdx++];
        grid[seat.row][seat.col] = SeatAssignment(
          student: student,
          seat: seat,
          method: 'RANDOM',
        );
        placedCount++;
      } else {
        overflow.add(student);
      }
    }

    return _Tier3Result(placedCount: placedCount, overflow: overflow);
  }

  // ── Single-book placement ───────────────────────────────────────

  SeatingResult _singleBookPlacement(
    int rows,
    int cols,
    List<StudentSeatInput> students,
    List<SeatHistoryEntry> history,
    int hallId,
    List<String> warnings,
    List<List<SeatAssignment?>> grid,
  ) {
    final totalSeats = rows * cols;

    final historySet = <String>{};
    for (final h in history) {
      historySet.add('${h.studentId}:${h.bookId}:${h.hallId}:${h.seatRow}:${h.seatColumn}');
    }

    final studentList = List<StudentSeatInput>.from(students)..shuffle();

    // Build ordered seat candidate positions (Row-by-Row, Col-by-Col)
    final availableSeats = <SeatPosition>[];
    
    // If student count <= half of hall capacity, use 1-seat gap interleaving for anti-cheating!
    final useGap = studentList.length <= (totalSeats ~/ 2);

    if (useGap) {
      // Pass 1: Checkerboard primary seats
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          if ((r + c) % 2 == 0) {
            availableSeats.add(SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1));
          }
        }
      }
      // Pass 2: Remaining seats if needed
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          if ((r + c) % 2 != 0) {
            availableSeats.add(SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1));
          }
        }
      }
    } else {
      // Sequential row-by-row fill
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          availableSeats.add(SeatPosition(row: r, col: c, seatNumber: r * cols + c + 1));
        }
      }
    }

    availableSeats.removeWhere((s) => grid[s.row][s.col] != null);

    final assignments = <SeatAssignment>[];
    final overflow = <StudentSeatInput>[];

    for (final student in studentList) {
      bool placed = false;

      // Try to find a seat without history conflict first
      for (int i = 0; i < availableSeats.length; i++) {
        final seat = availableSeats[i];
        final key = '${student.studentId}:${student.bookId}:$hallId:${seat.row}:${seat.col}';
        if (!historySet.contains(key)) {
          final assignment = SeatAssignment(
            student: student,
            seat: seat,
            method: useGap ? 'ANTI_ADJACENCY' : 'SEQUENTIAL',
          );
          grid[seat.row][seat.col] = assignment;
          assignments.add(assignment);
          availableSeats.removeAt(i);
          placed = true;
          break;
        }
      }

      // Fallback: use first available seat if history conflict occurs
      if (!placed && availableSeats.isNotEmpty) {
        final seat = availableSeats.removeAt(0);
        final assignment = SeatAssignment(
          student: student,
          seat: seat,
          method: useGap ? 'ANTI_ADJACENCY' : 'SEQUENTIAL',
        );
        grid[seat.row][seat.col] = assignment;
        assignments.add(assignment);
        placed = true;
      }

      if (!placed) {
        overflow.add(student);
      }
    }

    if (overflow.isNotEmpty) {
      warnings.add(
        'CRITICAL: ${overflow.length} students cannot fit in this hall ($totalSeats seats capacity). Please allocate an additional hall.'
      );
    }

    return SeatingResult(
      assignments: assignments,
      overflow: overflow,
      warnings: warnings,
      primaryMethod: useGap ? 'ANTI_ADJACENCY' : 'SEQUENTIAL',
      totalStudents: students.length,
      placedCount: assignments.length,
      tier1Count: useGap ? assignments.length : 0,
      tier3Count: useGap ? 0 : assignments.length,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  SeatingResult _buildResult(
    List<List<SeatAssignment?>> grid,
    int rows,
    int cols,
    List<StudentSeatInput> overflow,
    List<String> warnings,
    String method,
    int totalStudents,
    int t1,
    int t2,
    int t3,
  ) {
    final assignments = <SeatAssignment>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] != null) assignments.add(grid[r][c]!);
      }
    }

    return SeatingResult(
      assignments: assignments,
      overflow: overflow,
      warnings: warnings,
      primaryMethod: method,
      totalStudents: totalStudents,
      placedCount: assignments.length,
      tier1Count: t1,
      tier2Count: t2,
      tier3Count: t3,
    );
  }
}

class _TierResult {
  final int placedCount;
  final List<StudentSeatInput> unplaced;
  const _TierResult({required this.placedCount, required this.unplaced});
}

class _Tier3Result {
  final int placedCount;
  final List<StudentSeatInput> overflow;
  const _Tier3Result({required this.placedCount, required this.overflow});
}
