import 'package:claw_hub/domain/models/attachment_pick_result.dart';

/// 附件选择服务抽象。
///
/// 负责把平台相关的 `ImagePicker`/`FilePicker` 调用封装起来，返回平台无关的
/// [AttachmentPickResult]。UI 层（ChatRoomPage）通过此抽象选择附件，无需直接
/// 依赖 `dart:io`、`image_picker` 或 `file_picker`。
abstract class IAttachmentPickerService {
  /// 从相册或相机选择一张图片。
  ///
  /// [imageQuality] 为压缩质量（0-100），默认 85。
  /// 用户取消时返回 `null`。
  Future<AttachmentPickResult?> pickImage({
    required ImageSource source,
    int imageQuality,
  });

  /// 从文件系统选择一个文件。
  ///
  /// 用户取消时返回 `null`。
  Future<AttachmentPickResult?> pickFile();
}

/// 图片来源枚举，与 `image_picker` 的 [ImageSource] 对应但保持抽象层独立。
enum ImageSource { camera, gallery }
