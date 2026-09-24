class LibrarySettings {
  final double finePerDay;
  final int maxBooksPerStudent;
  final int defaultDueDays;
  final double lostBookFine;
  final double lostBookFoundFine;

  LibrarySettings({
    required this.finePerDay,
    required this.maxBooksPerStudent,
    required this.defaultDueDays,
    required this.lostBookFine,
    required this.lostBookFoundFine,
  });

  factory LibrarySettings.fromJson(Map<String, dynamic> json) {
    return LibrarySettings(
      finePerDay: (json['fine_per_day'] as num?)?.toDouble() ?? 5.0,
      maxBooksPerStudent: (json['max_books_per_student'] as num?)?.toInt() ?? 3,
      defaultDueDays: (json['default_due_days'] as num?)?.toInt() ?? 14,
      lostBookFine: (json['lost_book_fine'] as num?)?.toDouble() ?? 500.0,
      lostBookFoundFine: (json['lost_book_found_fine'] as num?)?.toDouble() ?? 100.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fine_per_day': finePerDay,
      'max_books_per_student': maxBooksPerStudent,
      'default_due_days': defaultDueDays,
      'lost_book_fine': lostBookFine,
      'lost_book_found_fine': lostBookFoundFine,
    };
  }
}

class LibraryCategory {
  final String id;
  final String name;
  final String? description;
  final int bookCount;

  LibraryCategory({
    required this.id,
    required this.name,
    this.description,
    required this.bookCount,
  });

  factory LibraryCategory.fromJson(Map<String, dynamic> json) {
    return LibraryCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      bookCount: (json['book_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'book_count': bookCount,
    };
  }
}

class LibraryBook {
  final String id;
  final String title;
  final String? author;
  final String? isbn;
  final String? categoryId;
  final String? categoryName;
  final String? publisher;
  final String language;
  final int totalCopies;
  final int availableCopies;
  final String? shelfLocation;
  final String? description;
  final String addedDate;
  final int? defaultDueDays;
  final double? lostBookFine;
  final double? lostBookFoundFine;
  final double? finePerDay;

  LibraryBook({
    required this.id,
    required this.title,
    this.author,
    this.isbn,
    this.categoryId,
    this.categoryName,
    this.publisher,
    required this.language,
    required this.totalCopies,
    required this.availableCopies,
    this.shelfLocation,
    this.description,
    required this.addedDate,
    this.defaultDueDays,
    this.lostBookFine,
    this.lostBookFoundFine,
    this.finePerDay,
  });

  factory LibraryBook.fromJson(Map<String, dynamic> json) {
    return LibraryBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String?,
      isbn: json['isbn'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      publisher: json['publisher'] as String?,
      language: json['language'] as String? ?? 'Urdu',
      totalCopies: (json['total_copies'] as num?)?.toInt() ?? 1,
      availableCopies: (json['available_copies'] as num?)?.toInt() ?? 1,
      shelfLocation: json['shelf_location'] as String?,
      description: json['description'] as String?,
      addedDate: json['added_date'] as String? ?? '',
      defaultDueDays: (json['default_due_days'] as num?)?.toInt(),
      lostBookFine: (json['lost_book_fine'] as num?)?.toDouble(),
      lostBookFoundFine: (json['lost_book_found_fine'] as num?)?.toDouble(),
      finePerDay: (json['fine_per_day'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'isbn': isbn,
      'category_id': categoryId,
      'publisher': publisher,
      'language': language,
      'total_copies': totalCopies,
      'available_copies': availableCopies,
      'shelf_location': shelfLocation,
      'description': description,
      'added_date': addedDate,
      'default_due_days': defaultDueDays,
      'lost_book_fine': lostBookFine,
      'lost_book_found_fine': lostBookFoundFine,
      'fine_per_day': finePerDay,
    };
  }
}

class LibraryTransaction {
  final String id;
  final String bookId;
  final String bookTitle;
  final String? bookAuthor;
  final String? studentId;
  final String? studentName;
  final String? studentGrNo;
  final String? studentVillage;
  final String? fatherName;
  final String? surname;
  final String? staffId;
  final String? staffName;
  final String? staffNo;
  final String? staffMobile;
  final String borrowerName;
  final String? hostelName;
  final String? roomNumber;
  final String? bedNumber;
  final String issueDate;
  final String dueDate;
  final String? returnDate;
  final String status;
  final String computedStatus;
  final int overdueDays;
  final double fineAmount;
  final String? remarks;
  final String? issuedBy;

  LibraryTransaction({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    this.bookAuthor,
    this.studentId,
    this.studentName,
    this.studentGrNo,
    this.studentVillage,
    this.fatherName,
    this.surname,
    this.staffId,
    this.staffName,
    this.staffNo,
    this.staffMobile,
    required this.borrowerName,
    this.hostelName,
    this.roomNumber,
    this.bedNumber,
    required this.issueDate,
    required this.dueDate,
    this.returnDate,
    required this.status,
    required this.computedStatus,
    required this.overdueDays,
    required this.fineAmount,
    this.remarks,
    this.issuedBy,
  });

  factory LibraryTransaction.fromJson(Map<String, dynamic> json) {
    return LibraryTransaction(
      id: json['id'] as String? ?? '',
      bookId: json['book_id'] as String? ?? '',
      bookTitle: json['book_title'] as String? ?? '',
      bookAuthor: json['book_author'] as String?,
      studentId: json['student_id'] as String?,
      studentName: json['student_name'] as String?,
      studentGrNo: json['student_gr_no'] as String?,
      studentVillage: json['student_village'] as String?,
      fatherName: json['father_name'] as String?,
      surname: json['surname'] as String?,
      staffId: json['staff_id'] as String?,
      staffName: json['staff_name'] as String?,
      staffNo: json['staff_no'] as String?,
      staffMobile: json['staff_mobile'] as String?,
      borrowerName: json['computed_borrower_name'] as String? ?? json['borrower_name'] as String? ?? '',
      hostelName: json['computed_hostel_name'] as String? ?? json['hostel_name'] as String?,
      roomNumber: json['computed_room_number'] as String? ?? json['room_number'] as String?,
      bedNumber: json['computed_bed_number'] as String? ?? json['bed_number'] as String?,
      issueDate: json['issue_date'] as String? ?? '',
      dueDate: json['due_date'] as String? ?? '',
      returnDate: json['return_date'] as String?,
      status: json['status'] as String? ?? '',
      computedStatus: json['computed_status'] as String? ?? '',
      overdueDays: (json['overdue_days'] as num?)?.toInt() ?? 0,
      fineAmount: (json['fine_amount'] as num?)?.toDouble() ?? 0.0,
      remarks: json['remarks'] as String?,
      issuedBy: json['issued_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'book_id': bookId,
      'student_id': studentId,
      'staff_id': staffId,
      'borrower_name': borrowerName,
      'hostel_name': hostelName,
      'room_number': roomNumber,
      'bed_number': bedNumber,
      'issue_date': issueDate,
      'due_date': dueDate,
      'return_date': returnDate,
      'status': status,
      'fine_amount': fineAmount,
      'remarks': remarks,
      'issued_by': issuedBy,
    };
  }
}

class CategoryBreakdownItem {
  final String name;
  final int count;

  CategoryBreakdownItem({required this.name, required this.count});

  factory CategoryBreakdownItem.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdownItem(
      name: json['name'] as String? ?? 'Unknown',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class LibraryStats {
  final int totalBooks;
  final int totalCopies;
  final int availableCopies;
  final int issuedCount;
  final int overdueCount;
  final int lostCount;
  final int returnedToday;
  final double totalFinesCollected;
  final List<CategoryBreakdownItem> categoryBreakdown;

  LibraryStats({
    required this.totalBooks,
    required this.totalCopies,
    required this.availableCopies,
    required this.issuedCount,
    required this.overdueCount,
    required this.lostCount,
    required this.returnedToday,
    required this.totalFinesCollected,
    required this.categoryBreakdown,
  });

  factory LibraryStats.fromJson(Map<String, dynamic> json) {
    var list = json['categoryBreakdown'] as List? ?? [];
    List<CategoryBreakdownItem> breakdown = list.map((i) => CategoryBreakdownItem.fromJson(i)).toList();

    return LibraryStats(
      totalBooks: (json['totalBooks'] as num?)?.toInt() ?? 0,
      totalCopies: (json['totalCopies'] as num?)?.toInt() ?? 0,
      availableCopies: (json['availableCopies'] as num?)?.toInt() ?? 0,
      issuedCount: (json['issuedCount'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdueCount'] as num?)?.toInt() ?? 0,
      lostCount: (json['lostCount'] as num?)?.toInt() ?? 0,
      returnedToday: (json['returnedToday'] as num?)?.toInt() ?? 0,
      totalFinesCollected: (json['totalFinesCollected'] as num?)?.toDouble() ?? 0.0,
      categoryBreakdown: breakdown,
    );
  }
}
