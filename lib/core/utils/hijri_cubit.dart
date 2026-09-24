import 'package:flutter_bloc/flutter_bloc.dart';
import '../network/api_client.dart';

class HijriState {
  final int adjustment;
  final bool isLoading;

  HijriState({this.adjustment = 0, this.isLoading = false});

  HijriState copyWith({int? adjustment, bool? isLoading}) {
    return HijriState(
      adjustment: adjustment ?? this.adjustment,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HijriCubit extends Cubit<HijriState> {
  HijriCubit() : super(HijriState());

  Future<void> loadAdjustment() async {
    emit(state.copyWith(isLoading: true));
    try {
      final response = await ApiClient().get('/settings/general');
      final adj = int.tryParse(response.data['hijri_adjustment']?.toString() ?? '0') ?? 0;
      emit(state.copyWith(adjustment: adj, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> updateAdjustment(int newAdj) async {
    emit(state.copyWith(isLoading: true));
    try {
      await ApiClient().put('/settings/general', data: {
        'hijri_adjustment': newAdj,
      });
      emit(state.copyWith(adjustment: newAdj, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false));
    }
  }
}
