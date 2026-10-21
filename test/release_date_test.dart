import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/models/music_models.dart';

void main() {
  group('releaseDateFromString', () {
    test('解析酷狗常见的日期写法', () {
      expect(releaseDateFromString('2003-07-31'), DateTime(2003, 7, 31));
      expect(releaseDateFromString('2003/07/31'), DateTime(2003, 7, 31));
      expect(releaseDateFromString('2003.07.31'), DateTime(2003, 7, 31));
      expect(releaseDateFromString('2003年07月31日'), DateTime(2003, 7, 31));
    });

    test('只给年份时归到 1 月 1 日', () {
      expect(releaseDateFromString('1993'), DateTime(1993, 1, 1));
    });

    test('非法日期与空值返回 null，不用当天兜底', () {
      expect(releaseDateFromString('2003-02-31'), isNull);
      expect(releaseDateFromString(''), isNull);
      expect(releaseDateFromString(null), isNull);
      expect(releaseDateFromString('未知'), isNull);
    });
  });

  group('releaseDateFromMillis', () {
    test('按 UTC+8 换算，跨时区不会差一天', () {
      // 1059580800000 = 2003-07-31 00:00:00 +08:00
      expect(releaseDateFromMillis(1059580800000), DateTime(2003, 7, 31));
    });

    test('秒级时间戳不会被当成 1970 年', () {
      expect(
        releaseDateFromMillis(1059580800, allowSeconds: true),
        DateTime(2003, 7, 31),
      );
    });

    test('空值与 0 返回 null', () {
      expect(releaseDateFromMillis(null), isNull);
      expect(releaseDateFromMillis(0), isNull);
    });
  });

  group('releaseDateFromSongJson', () {
    test('优先取日期字符串，其次取时间戳', () {
      expect(
        releaseDateFromSongJson({'PublishDate': '2021-12-08'}),
        DateTime(2021, 12, 8),
      );
      expect(
        releaseDateFromSongJson({'publishTime': 1059580800000}),
        DateTime(2003, 7, 31),
      );
      expect(
        releaseDateFromSongJson({
          'albuminfo': {'publish_time': '1993-09-09'},
        }),
        DateTime(1993, 9, 9),
      );
    });

    test('没有发行日期字段时返回 null', () {
      expect(releaseDateFromSongJson({'FileName': '某首歌'}), isNull);
    });
  });

  group('normalizeImageUrl', () {
    test('网易云 http 升级为 https', () {
      expect(
        normalizeImageUrl('http://p1.music.126.net/abc.jpg'),
        'https://p1.music.126.net/abc.jpg',
      );
    });

    test('酷狗占位符按尺寸替换', () {
      expect(
        normalizeImageUrl('http://imge.kugou.com/stdmusic/{size}/abc.jpg'),
        'http://imge.kugou.com/stdmusic/480/abc.jpg',
      );
    });
  });
}
