// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CallModelAdapter extends TypeAdapter<CallModel> {
  @override
  final int typeId = 1;

  @override
  CallModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final DateTime startedAt = CallModel._decodeDateTime(fields[4]);
    final DateTime? endedAt = CallModel._decodeNullableDateTime(fields[11]);
    final dynamic rawDuration = fields[13];
    final Duration? decodedDuration = CallModel._decodeDuration(
      rawDuration,
      startedAt: startedAt,
      endedAt: endedAt,
    );
    final int? storedDurationSeconds = rawDuration is num
        ? rawDuration.toInt()
        : decodedDuration?.inSeconds;
    return CallModel(
      callId: (fields[0] as String?) ?? '',
      callerId: (fields[1] as String?) ?? '',
      calleeId: (fields[2] as String?) ?? '',
      status: (fields[3] as String?) ?? 'ringing',
      timestamp: startedAt,
      isVideoCall: (fields[5] as bool?) ?? false,
      participants: CallModel._decodeParticipants(fields[6]),
      offer: CallModel._decodeMap(fields[7]),
      answer: CallModel._decodeMap(fields[8]),
      callerCandidates: CallModel._decodeList(fields[9]),
      calleeCandidates: CallModel._decodeList(fields[10]),
      endedAt: endedAt,
      endReason: fields[12] as String?,
      duration: decodedDuration,
      durationSeconds: storedDurationSeconds,
    );
  }

  @override
  void write(BinaryWriter writer, CallModel obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.callId)
      ..writeByte(1)
      ..write(obj.callerId)
      ..writeByte(2)
      ..write(obj.calleeId)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isVideoCall)
      ..writeByte(6)
      ..write(obj.participants)
      ..writeByte(7)
      ..write(obj.offer)
      ..writeByte(8)
      ..write(obj.answer)
      ..writeByte(9)
      ..write(obj.callerCandidates)
      ..writeByte(10)
      ..write(obj.calleeCandidates)
      ..writeByte(11)
      ..write(obj.endedAt)
      ..writeByte(12)
      ..write(obj.endReason)
      ..writeByte(13)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
