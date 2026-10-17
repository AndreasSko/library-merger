"""Build small, synthetic schema-16 archives using the Go library's template.

Usage: python3 scripts/build-playlist-test-fixtures.py [--go-source PATH] [--output DIR]
Needs a go-jwlm checkout (default: ../go-jwlm, else pass --go-source).
Output is deterministic, so regenerating should leave the fixtures unchanged.
"""
from pathlib import Path
import hashlib, json, shutil, sqlite3, tempfile, zipfile, struct, zlib

ROOT = Path(__file__).resolve().parents[1]
GO = ROOT.parent / 'go-jwlm'
OUT = ROOT / 'LibraryMergerTests/Fixtures'

def build(name, lists, change=None, thumbnail=None, publication=None):
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / 'userData.db'
        shutil.copyfile(GO / 'model/data/userData.db', db)
        c = sqlite3.connect(db)
        media = {}
        item = 0
        for tag, (title, labels) in enumerate(lists, 1):
            c.execute('INSERT INTO Tag VALUES (?, 2, ?)', (tag, title))
            for pos, label in enumerate(labels):
                item += 1
                c.execute('INSERT INTO PlaylistItem VALUES (?,?,?,?,?,?,?)',
                          (item,label,2500000000,None,1,pos%4,None))
                c.execute('INSERT INTO TagMap VALUES (?,?,NULL,NULL,?,?)',(item,item,tag,pos))
                if publication:
                    c.execute('INSERT INTO Location (LocationId,Track,IssueTagNumber,KeySymbol,MepsLanguage,Type,Title) VALUES (?,?,0,?,?,3,?)',
                              (item,publication['track'],publication['symbol'],publication['language'],publication['title']))
                    c.execute('INSERT INTO PlaylistItemLocationMap VALUES (?,?,2,?)',
                              (item,item,publication['durationTicks']))
                else:
                    file = f'{label}.bin'
                    if file not in media:
                        media[file] = (len(media)+1, ('synthetic media '+label).encode())
                        mid, data = media[file]
                        c.execute('INSERT INTO IndependentMedia VALUES (?,?,?,?,?)',
                                  (mid,file,file,'application/octet-stream',hashlib.sha256(data).hexdigest()))
                    mid, _ = media[file]
                    c.execute('INSERT INTO PlaylistItemIndependentMediaMap VALUES (?,?,?)',(item,mid,5000000000))
        if thumbnail:
            filename, data = thumbnail
            media[filename] = (len(media)+1, data)
            mid, _ = media[filename]
            c.execute('INSERT INTO IndependentMedia VALUES (?,?,?,?,?)',
                      (mid, filename, filename, 'image/png', hashlib.sha256(data).hexdigest()))
            c.execute('UPDATE PlaylistItem SET ThumbnailFilePath=?', (filename,))
        if change: c.executescript(change)
        # Schema triggers use wall time on every mutation. Freeze it before the
        # hash and ZIP are generated, including the otherwise untouched empty DB.
        c.execute("UPDATE LastModified SET LastModified='2020-01-01T00:00:00Z'")
        c.commit()
        assert c.execute('pragma integrity_check').fetchone()[0]=='ok'
        assert not c.execute('pragma foreign_key_check').fetchall()
        c.close()
        # SQLite stores its library version in this informational header field.
        # Preserve the template value so a different hosted SQLite build cannot
        # change otherwise identical synthetic archives.
        blob = bytearray(db.read_bytes())
        blob[96:100] = (GO/'model/data/userData.db').read_bytes()[96:100]
        db.write_bytes(blob)
        with sqlite3.connect(db.as_uri()+'?mode=ro',uri=True) as check:
            assert check.execute('pragma integrity_check').fetchone()[0]=='ok'
            assert not check.execute('pragma foreign_key_check').fetchall()
        blob = bytes(blob)
        manifest = json.loads((GO/'model/testdata/manifest_correct.json').read_text())
        manifest['userDataBackup']['hash'] = hashlib.sha256(blob).hexdigest()
        manifest['userDataBackup']['schemaVersion'] = 16
        with zipfile.ZipFile(OUT/f'{name}.jwlibrary','w',zipfile.ZIP_STORED) as z:
            def write(filename, data):
                entry = zipfile.ZipInfo(filename, date_time=(1980,1,1,0,0,0))
                entry.compress_type = zipfile.ZIP_STORED
                z.writestr(entry, data)
            write('userData.db',blob)
            write('manifest.json',json.dumps(manifest,sort_keys=True))
            for file, (_, data) in sorted(media.items()): write(file,data)

def main():
    import argparse
    global GO, OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--go-source', type=Path, default=GO)
    parser.add_argument('--output', type=Path, default=OUT)
    args = parser.parse_args()
    GO, OUT = args.go_source, args.output
    OUT.mkdir(parents=True,exist_ok=True)
    build('base',[('Common',['A','B','C'])])
    build('conflict',[('Common',['A','B','C'])], "UPDATE PlaylistItem SET Label='Changed A',EndAction=3 WHERE PlaylistItemId=1;")
    build('duration',[('Common',['A','B','C'])], 'UPDATE PlaylistItemIndependentMediaMap SET DurationTicks=6000000000 WHERE PlaylistItemId=1;')
    build('unsupported',[('Common',['A'])], """
    INSERT INTO PlaylistItemMarker VALUES (1,1,'Marker',0,1000000000,0);
    """)

    def pixel_png(red):
        def chunk(kind, payload):
            return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload))
        return (b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))
                +chunk(b'IDAT',zlib.compress(bytes([0,red,0,0]),level=0))+chunk(b'IEND',b''))

    # Identity/title/duration verified against JW's official metadata API. Only
    # source metadata is real: playlist settings and PNG artwork are fictional.
    publication = dict(symbol='jwb-142', track=1, language=0,
                       title='JW Broadcasting—October 2026', durationTicks=34346400000)
    changes = 'UPDATE PlaylistItem SET StartTrimOffsetTicks=25000000,EndAction=0;'
    preview = ('publication-preview.png', pixel_png(32))
    playlist = [('Offline publication example', ['October programme excerpt'])]
    build('publication-base', playlist, changes, thumbnail=preview, publication=publication)
    build('publication-action', playlist, changes+'UPDATE PlaylistItem SET EndAction=3;', thumbnail=preview, publication=publication)


if __name__ == '__main__':
    main()
