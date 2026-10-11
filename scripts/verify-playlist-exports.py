"""Inspect iOS-exported archives and compare original fixture scenarios."""
import argparse, hashlib, json, pathlib, sqlite3, tempfile, zipfile

MANDATORY_EXPORTS = {
 'front', 'empty', 'duration', 'conflict', 'conflict-left', 'conflict-again',
 'cancel-retry', 'cancel-retry-again', 'reset-after-conflict',
 'repeated-aba-abaa', 'mixed-hashes', 'thumbnail-auto', 'thumbnail-same-bytes', 'thumbnail-unpadded',
 'publication-action', 'publication-thumbnail',
}
ORIGINAL_SCENARIOS = {
 'scenario-1-insert-front', 'scenario-2-divergent-inserts',
 'scenario-3-separate-playlists', 'scenario-4-common-plus-new',
}
ORIGINAL_EXPORTS = ORIGINAL_SCENARIOS | {name+'-reverse' for name in ORIGINAL_SCENARIOS}


def validate_export_inventory(exports, require_originals=False):
 actual = {file.stem for file in exports.glob('*.jwlibrary')}
 required = MANDATORY_EXPORTS | (ORIGINAL_EXPORTS if require_originals else set())
 missing = sorted(required-actual)
 unexpected = sorted(actual-required)
 if missing or unexpected:
  raise AssertionError(f'Export inventory mismatch: missing={missing}, unexpected={unexpected}')
 return actual

def inspect(path):
 with zipfile.ZipFile(path) as z,tempfile.TemporaryDirectory() as d:
  blobs={n:z.read(n) for n in z.namelist()};manifest=json.loads(blobs['manifest.json'])
  assert hashlib.sha256(blobs['userData.db']).hexdigest()==manifest['userDataBackup']['hash']
  dbpath=pathlib.Path(d)/'db';dbpath.write_bytes(blobs['userData.db']);c=sqlite3.connect(dbpath);c.row_factory=sqlite3.Row
  assert not c.execute('pragma foreign_key_check').fetchall()
  assert c.execute('pragma integrity_check').fetchone()[0]=='ok'
  items=[]
  for row in c.execute('select t.Name,p.* from Tag t join TagMap tm on tm.TagId=t.TagId join PlaylistItem p on p.PlaylistItemId=tm.PlaylistItemId where t.Type=2 order by t.Name,tm.Position'):
   item=dict(row);id=item.pop('PlaylistItemId');thumb=item.pop('ThumbnailFilePath')
   item['thumbnailContent']=hashlib.sha256(blobs[thumb]).hexdigest() if thumb else None
   loc=[]
   for m in c.execute('select l.*,m.MajorMultimediaType,m.BaseDurationTicks from PlaylistItemLocationMap m join Location l on l.LocationId=m.LocationId where m.PlaylistItemId=?',(id,)):
    v=dict(m);v.pop('LocationId');loc.append(v)
   item['locations']=loc
   media=[]
   for m in c.execute('select im.*,m.DurationTicks from PlaylistItemIndependentMediaMap m join IndependentMedia im on im.IndependentMediaId=m.IndependentMediaId where m.PlaylistItemId=?',(id,)):
    v=dict(m);v.pop('IndependentMediaId');file=v.pop('FilePath');v['content']=hashlib.sha256(blobs[file]).hexdigest();v.pop('Hash',None);media.append(v)
   item['media']=media;items.append(item)
  media={row['Hash']:hashlib.sha256(blobs[row['FilePath']]).hexdigest() for row in c.execute('select * from IndependentMedia')}
  # Original JW archives can encode SHA-256 bytes without zero-padding.
  assert all(expected.lower() in (actual, ''.join(format(byte, 'x') for byte in bytes.fromhex(actual)))
             for expected,actual in media.items()), str(path)
  playlists=[row['Name'] for row in c.execute('select Name from Tag where Type=2 order by Name')]
  for tag in c.execute('select TagId from Tag where Type=2'):
   positions=[row['Position'] for row in c.execute('select Position from TagMap where TagId=? order by Position',(tag['TagId'],))]
   assert positions==list(range(len(positions))), str(path)
  c.close()
  return {'playlists':playlists,'items':items,'media':media}

def main():
 parser = argparse.ArgumentParser()
 parser.add_argument('exports', type=pathlib.Path)
 parser.add_argument('--originals', type=pathlib.Path)
 args = parser.parse_args()
 validate_export_inventory(args.exports, require_originals=args.originals is not None)
 report=[]
 for file in sorted(args.exports.glob('*.jwlibrary')):
  got=inspect(file)
  name=file.stem
  if name.startswith('scenario-') and args.originals:
   folder=name.removesuffix('-reverse')
   expected={'scenario-1-insert-front':'expected','scenario-2-divergent-inserts':'expected',
             'scenario-3-separate-playlists':'expected-two-playlists',
             'scenario-4-common-plus-new':'expected-three-playlists'}[folder]
   assert got==inspect(args.originals/folder/(expected+'.jwlibrary')), name
  if name in ['conflict','conflict-again','cancel-retry','cancel-retry-again']:
   assert got['items'][0]['Label']=='Changed A'
   assert got['items'][0]['EndAction']==3
  if name=='conflict-left': assert got['items'][0]['Label']=='A'
  if name=='duration': assert got['items'][0]['media'][0]['DurationTicks']==6000000000
  if name=='front': assert [v['Label'] for v in got['items']]==['X','A','B','C']
  if name in ['empty', 'reset-after-conflict']: assert [v['Label'] for v in got['items']]==['A','B','C']
  if name=='mixed-hashes':
   assert [v['Label'] for v in got['items']]==['A','A']
   assert all(v['EndAction']==0 for v in got['items'])
  if name=='repeated-aba-abaa':
   assert [v['Label'] for v in got['items']]==['A','B','A','A']
   assert all(v['EndAction']==(0 if v['Label']=='A' else 1) for v in got['items'])
  if name in ['thumbnail-auto','thumbnail-same-bytes','thumbnail-unpadded','publication-action','publication-thumbnail']:
   import importlib.util
   spec=importlib.util.spec_from_file_location('fixture_validator',pathlib.Path(__file__).with_name('validate-playlist-fixtures.py'))
   validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)
   fixtures=pathlib.Path(__file__).resolve().parents[1]/'LibraryMergerTests/Fixtures'
   if name in ['thumbnail-auto','publication-thumbnail']:
    source_names=(['thumbnail-old','thumbnail-new'] if name=='thumbnail-auto'
                  else ['publication-base','publication-thumbnail-new'])
    sources=[validator.inspect_archive(fixtures/(value+'.jwlibrary')) for value in source_names]
    assert all(not source['errors'] for source in sources), name
    expected_source=min(sources,key=lambda source:source['playlists'][0]['items'][0]['item']['thumbnailSha256'])
    expected=fixtures/(source_names[sources.index(expected_source)]+'.jwlibrary')
    source_media=set().union(*(set(inspect(fixtures/(value+'.jwlibrary'))['media'].values()) for value in source_names))
    assert set(got['media'].values())==source_media, (name,'media payload union differs')
   else:
    expected=fixtures/(name+'.jwlibrary')
   actual_snapshot=validator.inspect_archive(file);expected_snapshot=validator.inspect_archive(expected)
   assert not actual_snapshot['errors'], actual_snapshot['errors']
   assert actual_snapshot['playlists']==expected_snapshot['playlists'], name
  report.append({'case':name,'passed':True,'playlistItems':len(got['items']),
                 'mediaFiles':len(got['media'])})
 assert report, 'No exported archives found'
 print(json.dumps(report,indent=2))

if __name__=='__main__': main()
