import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

class ReelsTab extends StatefulWidget {
  const ReelsTab({super.key});
  @override
  State<ReelsTab> createState() => _ReelsTabState();
}

class _ReelsTabState extends State<ReelsTab> {
  final _db = FirebaseFirestore.instance;
  Future<void> _createPost() async {
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const _CreateReelScreen()));
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đăng ảnh kèm nhạc thành công')));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('reels').orderBy('createdAt', descending: true).limit(50).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Không tải được Reels: ${snapshot.error}\nKiểm tra Firestore Rules.', textAlign: TextAlign.center)));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final posts = snapshot.data!.docs;
        if (posts.isEmpty) return const Center(child: Text('Chưa có bài đăng. Nhấn + để đăng ảnh kèm nhạc.'));
        return ListView.builder(itemCount: posts.length, itemBuilder: (_, index) {
          final data = posts[index].data();
          return _ReelCard(key: ValueKey(posts[index].id), data: data);
        });
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPost, icon: const Icon(Icons.add_photo_alternate), label: const Text('Đăng Reels')),
  );
}

class _ReelCard extends StatefulWidget {
  final Map<String, dynamic> data;
  const _ReelCard({super.key, required this.data});
  @override
  State<_ReelCard> createState() => _ReelCardState();
}
class _ReelCardState extends State<_ReelCard> {
  final _player = AudioPlayer();
  bool _playing = false;
  @override
  void dispose() { _player.dispose(); super.dispose(); }
  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        final url = (widget.data['musicUrl'] ?? '').toString();
        if (url.isEmpty) return;
        if (_player.audioSource == null) await _player.setUrl(url);
        unawaited(_player.play());
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi phát nhạc: $e')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final image = (widget.data['imageUrl'] ?? '').toString();
    final music = (widget.data['musicUrl'] ?? '').toString();
    return Card(margin: const EdgeInsets.all(12), clipBehavior: Clip.antiAlias, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(
          (widget.data['authorName'] ?? 'Người dùng').toString(),
          style: const TextStyle(fontWeight: FontWeight.bold))),
      if (image.isNotEmpty) AspectRatio(aspectRatio: 4 / 5,
          child: Image.network(image, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(child: Text('Không tải được ảnh')))),
      if ((widget.data['caption'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.all(12), child: Text(widget.data['caption'].toString())),
      if (music.isNotEmpty) ListTile(
        leading: IconButton(icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
            onPressed: _toggle),
        title: Text((widget.data['musicName'] ?? 'Âm nhạc').toString(), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: const Text('Nhấn để phát/tạm dừng nhạc'),
      ),
    ]));
  }
}

class _CreateReelScreen extends StatefulWidget {
  const _CreateReelScreen();
  @override
  State<_CreateReelScreen> createState() => _CreateReelScreenState();
}
class _CreateReelScreenState extends State<_CreateReelScreen> {
  final _caption = TextEditingController();
  XFile? _image;
  PlatformFile? _audio;
  bool _uploading = false;
  @override
  void dispose() { _caption.dispose(); super.dispose(); }
  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (mounted) setState(() => _image = file);
  }
  Future<void> _pickMusic() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (mounted && result != null && result.files.isNotEmpty) {
      setState(() => _audio = result.files.first);
    }
  }
  Future<void> _publish() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy chọn một ảnh')));
      return;
    }
    setState(() => _uploading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final post = FirebaseFirestore.instance.collection('reels').doc();
      final imageBytes = await _image!.readAsBytes();
      final imageRef = FirebaseStorage.instance.ref('reels/${user.uid}/${post.id}/image.jpg');
      await imageRef.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
      final imageUrl = await imageRef.getDownloadURL();
      String? musicUrl;
      if (_audio?.bytes != null) {
        final musicRef = FirebaseStorage.instance.ref('reels/${user.uid}/${post.id}/music');
        await musicRef.putData(_audio!.bytes!, SettableMetadata(contentType: _audio!.extension?.toLowerCase() == 'mp3' ? 'audio/mpeg' : 'audio/mp4'));
        musicUrl = await musicRef.getDownloadURL();
      }
      await post.set({
        'authorId': user.uid,
        'authorName': user.displayName ?? user.email ?? 'Người dùng',
        'caption': _caption.text.trim(),
        'imageUrl': imageUrl,
        'musicUrl': musicUrl,
        'musicName': _audio?.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Không đăng được Reels: $error')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đăng ảnh kèm nhạc')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(onPressed: _uploading ? null : _pickImage,
          icon: const Icon(Icons.photo_library),
          label: Text(_image == null ? 'Chọn ảnh từ điện thoại' : 'Đã chọn: ${_image!.name}')),
      OutlinedButton.icon(onPressed: _uploading ? null : _pickMusic,
          icon: const Icon(Icons.music_note),
          label: Text(_audio == null ? 'Thêm nhạc từ thiết bị (không bắt buộc)' : _audio!.name)),
      const SizedBox(height: 12),
      TextField(controller: _caption, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Chú thích', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _uploading ? null : _publish,
          icon: _uploading ? const SizedBox(height: 18, width: 18,
              child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
          label: Text(_uploading ? 'Đang tải lên...' : 'Đăng bài')),
      const SizedBox(height: 12),
      const Text('Chỉ đăng nhạc bạn có quyền sử dụng. Ảnh và âm thanh được lưu trên Firebase Storage.'),
    ])),
  );
}
