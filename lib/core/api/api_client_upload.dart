import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';
import 'api_exception.dart';
import 'endpoints.dart';

/// multipart/form-data 构造（对齐 MultipartFormData.swift，§4.1）。
///
/// 文本字段（仅 upload 的 `session_id`）+ 文件字段（`file`）+ 结束边界
/// `--<boundary>--\r\n`。
class MultipartBody {
  const MultipartBody._();

  static Uint8List build({
    required String boundary,
    String? textFieldName,
    String? textValue,
    required String fileFieldName,
    required String filename,
    required Uint8List fileBytes,
  }) {
    final buffer = BytesBuilder();
    void write(String value) => buffer.add(utf8.encode(value));

    if (textFieldName != null) {
      write('--$boundary\r\n');
      write('Content-Disposition: form-data; name="$textFieldName"\r\n');
      write('\r\n');
      write('$textValue\r\n');
    }
    write('--$boundary\r\n');
    write(
      'Content-Disposition: form-data; name="$fileFieldName"; filename="$filename"\r\n',
    );
    write('Content-Type: application/octet-stream\r\n');
    write('\r\n');
    buffer.add(fileBytes);
    write('\r\n--$boundary--\r\n');
    return buffer.toBytes();
  }
}

/// upload / transcribe / tts 域方法（3 个端点）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientUpload on ApiClient {
  /// 客户端单文件预检上限：20MB（Models/UploadResponse.swift
  /// `maximumUploadBytes`；服务端上限为 10 附件 / 64MiB 总量，超限错误透传）。
  static const int maximumUploadBytes = 20 * 1024 * 1024;

  /// POST /api/upload — multipart：文本字段 `session_id` + 文件字段 `file`。
  ///
  /// 单文件 >20MB 本地拒绝（[UploadFileTooLargeException]）；服务端
  /// 64MiB/10 附件超限以 4xx + `{error}` body 透传为 [HttpException]。
  Future<Object?> uploadFile({
    required String sessionId,
    required Uint8List data,
    required String filename,
    String? boundary,
  }) async {
    if (data.length > maximumUploadBytes) {
      throw const UploadFileTooLargeException();
    }
    final resolvedBoundary = boundary ?? _generateBoundary();
    final body = MultipartBody.build(
      boundary: resolvedBoundary,
      textFieldName: 'session_id',
      textValue: sessionId,
      fileFieldName: 'file',
      filename: filename,
      fileBytes: data,
    );
    final response = await sendUnchecked(
      Endpoint.upload,
      method: 'POST',
      data: body,
      contentType: 'multipart/form-data; boundary=$resolvedBoundary',
    );
    final status = response.statusCode;
    if (status == 401) throw const UnauthorizedException();
    if (status < 200 || status >= 300) {
      throw HttpException.fromBody(
        status,
        utf8.decode(response.data, allowMalformed: true),
      );
    }
    return _decodeJsonOrThrow(response.data);
  }

  /// POST /api/transcribe — multipart：仅文件字段 `file`。
  ///
  /// 服务端 503/400/413 也带 `{ok, transcript, error}` body，因此非 2xx 也先
  /// 尝试解码；仅 401 映射为 [UnauthorizedException]。
  Future<Object?> transcribeAudio({
    required Uint8List data,
    required String filename,
    String? boundary,
  }) async {
    final resolvedBoundary = boundary ?? _generateBoundary();
    final body = MultipartBody.build(
      boundary: resolvedBoundary,
      fileFieldName: 'file',
      filename: filename,
      fileBytes: data,
    );
    final response = await sendUnchecked(
      Endpoint.transcribe,
      method: 'POST',
      data: body,
      contentType: 'multipart/form-data; boundary=$resolvedBoundary',
    );
    final status = response.statusCode;
    if (status == 401) throw const UnauthorizedException();

    final text = utf8.decode(response.data, allowMalformed: true);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, Object?>) {
      return decoded; // 无论 2xx 与否，body 形状对就返回（调用方检查 .error）。
    }
    if (status < 200 || status >= 300) {
      throw HttpException.fromBody(status, text);
    }
    return decoded;
  }

  /// POST /api/tts {text, voice} — 原始音频字节（audio/mpeg），Accept=`*/*`；
  /// engine 默认 edge，rate/pitch 不发。
  Future<Uint8List> synthesizeSpeech({
    required String text,
    required String voice,
  }) => sendData(
    Endpoint.tts,
    method: 'POST',
    body: {'text': text, 'voice': voice},
    accept: '*/*',
  );

  Object? _decodeJsonOrThrow(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw DecodingException('响应 JSON 解析失败：${error.message}');
    }
  }

  String _generateBoundary() =>
      'Boundary-${DateTime.now().microsecondsSinceEpoch.toRadixString(16).toUpperCase()}';
}
