import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/library_repository.dart';

// ─── BLoC EVENTS ─────────────────────────────────────────────────────
abstract class LibraryEvent {}

class LoadLibraryData extends LibraryEvent {
  final String? search;
  final String? categoryId;
  final String? availability;
  final String? txStatus;
  final String? txStudentId;
  final String? txBookId;
  final String? startDate;
  final String? endDate;

  LoadLibraryData({
    this.search,
    this.categoryId,
    this.availability,
    this.txStatus,
    this.txStudentId,
    this.txBookId,
    this.startDate,
    this.endDate,
  });
}

class UpdateSettingsEvent extends LibraryEvent {
  final LibrarySettings settings;
  UpdateSettingsEvent(this.settings);
}

class CreateCategoryEvent extends LibraryEvent {
  final String name;
  final String? description;
  CreateCategoryEvent({required this.name, this.description});
}

class UpdateCategoryEvent extends LibraryEvent {
  final String id;
  final String name;
  final String? description;
  UpdateCategoryEvent({required this.id, required this.name, this.description});
}

class DeleteCategoryEvent extends LibraryEvent {
  final String id;
  DeleteCategoryEvent(this.id);
}

class CreateBookEvent extends LibraryEvent {
  final LibraryBook book;
  CreateBookEvent(this.book);
}

class UpdateBookEvent extends LibraryEvent {
  final String id;
  final LibraryBook book;
  UpdateBookEvent({required this.id, required this.book});
}

class DeleteBookEvent extends LibraryEvent {
  final String id;
  DeleteBookEvent(this.id);
}

class IssueBookEvent extends LibraryEvent {
  final String? transactionId;
  final String? studentId;
  final String? staffId;
  final String? borrowerName;
  final String? hostelName;
  final String? roomNumber;
  final String? bedNumber;
  final String bookId;
  final String? dueDate;
  IssueBookEvent({
    this.transactionId,
    this.studentId,
    this.staffId,
    this.borrowerName,
    this.hostelName,
    this.roomNumber,
    this.bedNumber,
    required this.bookId,
    this.dueDate,
  });
}

class ReturnBookEvent extends LibraryEvent {
  final String transactionId;
  final String? remarks;
  final double? customFine;
  ReturnBookEvent({required this.transactionId, this.remarks, this.customFine});
}

class MarkBookLostEvent extends LibraryEvent {
  final String transactionId;
  final String? remarks;
  MarkBookLostEvent({required this.transactionId, this.remarks});
}

class DeleteTransactionEvent extends LibraryEvent {
  final String transactionId;
  DeleteTransactionEvent(this.transactionId);
}

class UpdateTransactionEvent extends LibraryEvent {
  final String transactionId;
  final String? dueDate;
  final String? remarks;
  final String? status;
  final double? fineAmount;

  UpdateTransactionEvent({
    required this.transactionId,
    this.dueDate,
    this.remarks,
    this.status,
    this.fineAmount,
  });
}

// ─── BLoC STATES ─────────────────────────────────────────────────────
abstract class LibraryState {}

class LibraryInitial extends LibraryState {}

class LibraryLoading extends LibraryState {}

class LibraryLoaded extends LibraryState {
  final LibrarySettings settings;
  final List<LibraryCategory> categories;
  final List<LibraryBook> books;
  final List<LibraryTransaction> transactions;
  final LibraryStats stats;

  LibraryLoaded({
    required this.settings,
    required this.categories,
    required this.books,
    required this.transactions,
    required this.stats,
  });
}

class LibraryError extends LibraryState {
  final String message;
  LibraryError(this.message);
}

// ─── BLoC CLASS ──────────────────────────────────────────────────────
class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final LibraryRepository repository;

  // Track filters to preserve them on reload
  String? _search;
  String? _categoryId;
  String? _availability;
  String? _txStatus;
  String? _txStudentId;
  String? _txBookId;
  String? _startDate;
  String? _endDate;

  LibraryBloc({required this.repository}) : super(LibraryInitial()) {
    on<LoadLibraryData>(_onLoadLibraryData);
    on<UpdateSettingsEvent>(_onUpdateSettings);
    on<CreateCategoryEvent>(_onCreateCategory);
    on<UpdateCategoryEvent>(_onUpdateCategory);
    on<DeleteCategoryEvent>(_onDeleteCategory);
    on<CreateBookEvent>(_onCreateBook);
    on<UpdateBookEvent>(_onUpdateBook);
    on<DeleteBookEvent>(_onDeleteBook);
    on<IssueBookEvent>(_onIssueBook);
    on<ReturnBookEvent>(_onReturnBook);
    on<MarkBookLostEvent>(_onMarkBookLost);
    on<DeleteTransactionEvent>(_onDeleteTransaction);
    on<UpdateTransactionEvent>(_onUpdateTransaction);
  }

  String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      return error.response?.data?['message'] ??
          error.response?.data?['error'] ??
          error.message ??
          'Server error occurred.';
    }
    return error.toString();
  }

  Future<void> _onLoadLibraryData(LoadLibraryData event, Emitter<LibraryState> emit) async {
    emit(LibraryLoading());
    try {
      _search = event.search ?? _search;
      _categoryId = event.categoryId ?? _categoryId;
      _availability = event.availability ?? _availability;
      _txStatus = event.txStatus ?? _txStatus;
      _txStudentId = event.txStudentId ?? _txStudentId;
      _txBookId = event.txBookId ?? _txBookId;
      _startDate = event.startDate ?? _startDate;
      _endDate = event.endDate ?? _endDate;

      final settings = await repository.getSettings();
      final categories = await repository.getCategories();
      final books = await repository.getBooks(
        search: _search,
        categoryId: _categoryId,
        availability: _availability,
      );
      final transactions = await repository.getTransactions(
        status: _txStatus,
        studentId: _txStudentId,
        bookId: _txBookId,
        startDate: _startDate,
        endDate: _endDate,
      );
      final stats = await repository.getStats();

      emit(LibraryLoaded(
        settings: settings,
        categories: categories,
        books: books,
        transactions: transactions,
        stats: stats,
      ));
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onUpdateSettings(UpdateSettingsEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.updateSettings(event.settings);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onCreateCategory(CreateCategoryEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.createCategory(event.name, event.description);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onUpdateCategory(UpdateCategoryEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.updateCategory(event.id, event.name, event.description);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onDeleteCategory(DeleteCategoryEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.deleteCategory(event.id);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onCreateBook(CreateBookEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.createBook(event.book);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onUpdateBook(UpdateBookEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.updateBook(event.id, event.book);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onDeleteBook(DeleteBookEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.deleteBook(event.id);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onIssueBook(IssueBookEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.issueBook(
        transactionId: event.transactionId,
        studentId: event.studentId,
        staffId: event.staffId,
        borrowerName: event.borrowerName,
        hostelName: event.hostelName,
        roomNumber: event.roomNumber,
        bedNumber: event.bedNumber,
        bookId: event.bookId,
        dueDate: event.dueDate,
      );
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onReturnBook(ReturnBookEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.returnBook(
        event.transactionId,
        remarks: event.remarks,
        customFine: event.customFine,
      );
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onMarkBookLost(MarkBookLostEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.markBookLost(event.transactionId, event.remarks);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onDeleteTransaction(DeleteTransactionEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.deleteTransaction(event.transactionId);
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }

  Future<void> _onUpdateTransaction(UpdateTransactionEvent event, Emitter<LibraryState> emit) async {
    try {
      await repository.updateTransaction(
        transactionId: event.transactionId,
        dueDate: event.dueDate,
        remarks: event.remarks,
        status: event.status,
        fineAmount: event.fineAmount,
      );
      add(LoadLibraryData());
    } catch (e) {
      emit(LibraryError(_getErrorMessage(e)));
    }
  }
}
