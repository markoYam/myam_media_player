import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/data/innertube_parser.dart';

Map<String, Object?> runs(String text, {String? channelId}) => {
      'runs': [
        {
          'text': text,
          if (channelId != null)
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': channelId},
            },
        },
      ],
    };

void main() {
  test('playlistVideoRenderer (página de la lista), incluso sin canal', () {
    final json = {
      'contents': [
        {
          'playlistVideoRenderer': {
            'videoId': 'aaaaaaaaaaa',
            'title': runs('Rayando el sol'),
            'shortBylineText': runs('Maná', channelId: 'UCaaaaaaaaaaaaaaaaaaaaaa'),
            'lengthSeconds': '257',
          },
        },
        {
          // Sin canal: la librería lo descartaba.
          'playlistVideoRenderer': {'videoId': 'bbbbbbbbbbb', 'title': runs('Oye mi amor'), 'lengthText': {'simpleText': '4:38'}},
        },
      ],
    };
    final v = InnerTubeParser.videos(json);
    expect(v.map((e) => e.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    expect(v.first.author, 'Maná');
    expect(v.first.channelId, 'UCaaaaaaaaaaaaaaaaaaaaaa');
    expect(v.first.duration, const Duration(seconds: 257));
    expect(v.last.duration, const Duration(minutes: 4, seconds: 38));
  });

  test('playlistPanelVideoRenderer (panel en "ver video")', () {
    final json = {
      'playlist': {
        'contents': [
          {
            'playlistPanelVideoRenderer': {
              'videoId': 'ccccccccccc',
              'title': {'simpleText': 'Labios compartidos'},
              'shortBylineText': runs('Maná'),
              'lengthText': {'simpleText': '1:02:03'},
            },
          },
        ],
      },
    };
    final v = InnerTubeParser.videos(json).single;
    expect(v.title, 'Labios compartidos');
    expect(v.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('lockupViewModel (formato nuevo)', () {
    final json = {
      'lockupViewModel': {
        'contentId': 'ddddddddddd',
        'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
        'contentImage': {
          'thumbnailViewModel': {
            'overlays': [
              {
                'thumbnailOverlayBadgeViewModel': {
                  'thumbnailBadges': [
                    {'thumbnailBadgeViewModel': {'text': '5:12'}},
                  ],
                },
              },
            ],
          },
        },
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {'content': 'Clavado en un bar'},
            'metadata': {
              'contentMetadataViewModel': {
                'metadataRows': [
                  {
                    'metadataParts': [
                      {'text': {'content': 'Maná'}},
                    ],
                  },
                ],
              },
            },
          },
        },
      },
    };
    final v = InnerTubeParser.videos(json).single;
    expect(v.id, 'ddddddddddd');
    expect(v.title, 'Clavado en un bar');
    expect(v.author, 'Maná');
    expect(v.duration, const Duration(minutes: 5, seconds: 12));
  });

  test('ignora listas dentro de resultados y repetidos', () {
    final json = [
      {'lockupViewModel': {'contentId': 'PLxxxxxxxxxxxxxxxx', 'contentType': 'LOCKUP_CONTENT_TYPE_PLAYLIST'}},
      {'videoRenderer': {'videoId': 'eeeeeeeeeee', 'title': runs('A')}},
      {'videoRenderer': {'videoId': 'eeeeeeeeeee', 'title': runs('A')}},
      {'videoRenderer': {'videoId': 'corto', 'title': runs('B')}},
    ];
    expect(InnerTubeParser.videos(json).map((e) => e.id), ['eeeeeeeeeee']);
  });

  test('continuación', () {
    final json = {
      'contents': [
        {'continuationItemRenderer': {'continuationEndpoint': {'continuationCommand': {'token': 'TOKEN123'}}}},
      ],
    };
    expect(InnerTubeParser.continuation(json), 'TOKEN123');
    expect(InnerTubeParser.continuation({'a': 1}), isNull);
  });

  test('duraciones', () {
    expect(InnerTubeParser.parseClock('3:45'), const Duration(minutes: 3, seconds: 45));
    expect(InnerTubeParser.parseClock('EN VIVO'), isNull);
  });
}
