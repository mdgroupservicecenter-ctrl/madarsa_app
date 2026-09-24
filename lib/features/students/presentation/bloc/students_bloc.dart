import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/student_repository.dart';
import '../../../../core/services/firebase_service.dart';

abstract class StudentsEvent {}

class LoadStudents extends StudentsEvent {
  final bool silent;
  LoadStudents({this.silent = false});
}

class SearchStudents extends StudentsEvent {
  final String query;
  SearchStudents(this.query);
}

class LoadStudentByGRNo extends StudentsEvent {
  final String grNo;
  LoadStudentByGRNo(this.grNo);
}

class LoadStudentDetails extends StudentsEvent {
  final String id;
  LoadStudentDetails(this.id);
}

class CreateStudent extends StudentsEvent {
  final Student student;
  CreateStudent(this.student);
}

class UpdateStudent extends StudentsEvent {
  final Student student;
  UpdateStudent(this.student);
}

class DeleteStudent extends StudentsEvent {
  final String id;
  DeleteStudent(this.id);
}

class BulkDeleteStudents extends StudentsEvent {
  final List<String> studentIds;
  BulkDeleteStudents(this.studentIds);
}

class BulkAssignCategory extends StudentsEvent {
  final List<String> studentIds;
  final String category;
  BulkAssignCategory(this.studentIds, this.category);
}

class BulkAssignDivision extends StudentsEvent {
  final List<String> studentIds;
  final String division;
  final String? subDepartmentId;
  final String? subDepartmentName;
  BulkAssignDivision(
    this.studentIds,
    this.division, {
    this.subDepartmentId,
    this.subDepartmentName,
  });
}

class UploadStudentDocument extends StudentsEvent {
  final String studentId;
  final String documentName;
  final String filePath;
  UploadStudentDocument({
    required this.studentId,
    required this.documentName,
    required this.filePath,
  });
}

class DeleteStudentDocument extends StudentsEvent {
  final String studentId;
  final String documentId;
  DeleteStudentDocument(this.studentId, this.documentId);
}

class GetNextGRNo extends StudentsEvent {}

class CalculateAge extends StudentsEvent {
  final String dob;
  final String? admissionDate;
  CalculateAge(this.dob, {this.admissionDate});
}

abstract class StudentsState {}

class StudentsInitial extends StudentsState {}

class StudentsLoading extends StudentsState {}

class StudentsLoaded extends StudentsState {
  final List<Student> students;
  final String? message;
  StudentsLoaded(this.students, {this.message});
}

class StudentDetailsLoaded extends StudentsState {
  final Student student;
  final String? message;
  StudentDetailsLoaded(this.student, {this.message});
}

class StudentByGRNoLoaded extends StudentsState {
  final Student student;
  StudentByGRNoLoaded(this.student);
}

class NextGRNoLoaded extends StudentsState {
  final String grNo;
  NextGRNoLoaded(this.grNo);
}

class AgeCalculated extends StudentsState {
  final String admissionTimeAge;
  final String nowAge;
  AgeCalculated(this.admissionTimeAge, this.nowAge);
}

class StudentsError extends StudentsState {
  final String message;
  StudentsError(this.message);
}

class StudentsBloc extends Bloc<StudentsEvent, StudentsState> {
  final StudentRepository repository;
  StreamSubscription<bool>? _cloudSub;

  StudentsBloc({required this.repository}) : super(StudentsInitial()) {
    on<LoadStudents>(_onLoadStudents);
    on<SearchStudents>(_onSearchStudents);
    on<LoadStudentByGRNo>(_onLoadStudentByGRNo);
    on<LoadStudentDetails>(_onLoadStudentDetails);
    on<CreateStudent>(_onCreateStudent);
    on<UpdateStudent>(_onUpdateStudent);
    on<DeleteStudent>(_onDeleteStudent);
    on<BulkDeleteStudents>(_onBulkDeleteStudents);
    on<UploadStudentDocument>(_onUploadStudentDocument);
    on<DeleteStudentDocument>(_onDeleteStudentDocument);
    on<GetNextGRNo>(_onGetNextGRNo);
    on<CalculateAge>(_onCalculateAge);
    on<BulkAssignCategory>(_onBulkAssignCategory);
    on<BulkAssignDivision>(_onBulkAssignDivision);

    _cloudSub = FirebaseService.onCloudUpdated.listen((_) {
      add(LoadStudents(silent: true));
    });
  }

  @override
  Future<void> close() {
    _cloudSub?.cancel();
    return super.close();
  }

  Future<void> _onLoadStudents(
    LoadStudents event,
    Emitter<StudentsState> emit,
  ) async {
    if (!event.silent && state is! StudentsLoaded) {
      emit(StudentsLoading());
    }
    try {
      final students = await repository.getAllStudents();
      emit(StudentsLoaded(students));
    } catch (e) {
      if (state is! StudentsLoaded) {
        emit(StudentsError(e.toString()));
      }
    }
  }

  Future<void> _onSearchStudents(
    SearchStudents event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      if (event.query.isEmpty) {
        final students = await repository.getAllStudents();
        emit(StudentsLoaded(students));
      } else {
        final students = await repository.searchStudents(event.query);
        emit(StudentsLoaded(students));
      }
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onLoadStudentByGRNo(
    LoadStudentByGRNo event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      final student = await repository.getStudentByGRNo(event.grNo);
      emit(StudentByGRNoLoaded(student));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onLoadStudentDetails(
    LoadStudentDetails event,
    Emitter<StudentsState> emit,
  ) async {
    emit(StudentsLoading());
    try {
      final student = await repository.getStudentById(event.id);
      emit(StudentDetailsLoaded(student));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onCreateStudent(
    CreateStudent event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.createStudent(event.student);
      add(LoadStudents(silent: true));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onUpdateStudent(
    UpdateStudent event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.updateStudent(event.student);
      if (state is StudentDetailsLoaded) {
        add(LoadStudentDetails(event.student.id));
      } else {
        add(LoadStudents(silent: true));
      }
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onDeleteStudent(
    DeleteStudent event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.deleteStudent(event.id);
      add(LoadStudents(silent: true));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onBulkDeleteStudents(
    BulkDeleteStudents event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.bulkDeleteStudents(event.studentIds);
      add(LoadStudents(silent: true));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onUploadStudentDocument(
    UploadStudentDocument event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.uploadDocument(
        event.studentId,
        event.documentName,
        event.filePath,
      );
      if (state is StudentDetailsLoaded) {
        add(LoadStudentDetails(event.studentId));
      }
    } catch (e) {
      emit(StudentsError(e.toString()));
      if (state is StudentDetailsLoaded)
        add(LoadStudentDetails(event.studentId));
    }
  }

  Future<void> _onDeleteStudentDocument(
    DeleteStudentDocument event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.deleteDocument(event.studentId, event.documentId);
      if (state is StudentDetailsLoaded) {
        add(LoadStudentDetails(event.studentId));
      }
    } catch (e) {
      emit(StudentsError(e.toString()));
      if (state is StudentDetailsLoaded)
        add(LoadStudentDetails(event.studentId));
    }
  }

  Future<void> _onGetNextGRNo(
    GetNextGRNo event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      final grNo = await repository.getNextGRNo();
      emit(NextGRNoLoaded(grNo));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onCalculateAge(
    CalculateAge event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      final result = await repository.getAgeCalculation(
        event.dob,
        date: event.admissionDate,
      );
      emit(
        AgeCalculated(
          result['admission_time_age'] ?? '',
          result['now_age'] ?? '',
        ),
      );
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onBulkAssignCategory(
    BulkAssignCategory event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.bulkAssignCategory(event.studentIds, event.category);
      add(LoadStudents(silent: true));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }

  Future<void> _onBulkAssignDivision(
    BulkAssignDivision event,
    Emitter<StudentsState> emit,
  ) async {
    try {
      await repository.bulkAssignDivision(
        event.studentIds,
        event.division,
        subDepartmentId: event.subDepartmentId,
        subDepartmentName: event.subDepartmentName,
      );
      add(LoadStudents(silent: true));
    } catch (e) {
      emit(StudentsError(e.toString()));
    }
  }
}
