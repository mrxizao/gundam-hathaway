"""Losslessly deduplicate identical payloads in a standalone Godot 4 PCK v4.
All resource paths and entry metadata are preserved. Never modifies the input.
Usage: python deduplicate_pck.py input.pck output.pck
"""
from pathlib import Path
import hashlib,struct,sys,json

def read_directory(path):
 with path.open('rb') as f:
  header=f.read(112)
  if header[:4]!=b'GDPC' or struct.unpack_from('<I',header,4)[0]!=4:raise ValueError('Expected standalone PCK v4')
  flags=struct.unpack_from('<I',header,20)[0]
  if flags!=2:raise ValueError('Unsupported flags (encrypted/embedded packs are not modified)')
  base,directory=struct.unpack_from('<QQ',header,24)
  f.seek(directory);count=struct.unpack('<I',f.read(4))[0];entries=[]
  for _ in range(count):
   length=struct.unpack('<I',f.read(4))[0];name=f.read(length)
   offset,size=struct.unpack('<QQ',f.read(16));digest=f.read(16);entry_flags=f.read(4)
   if entry_flags!=b'\0'*4:raise ValueError('Unsupported entry flags')
   entries.append((name,offset,size,digest,entry_flags))
 return header,base,entries

def main():
 source,target=map(Path,sys.argv[1:3])
 if source.resolve()==target.resolve() or target.exists():raise ValueError('Output must be a new file')
 header,base,entries=read_directory(source);unique={};mapped=[]
 with source.open('rb') as src,target.open('xb') as dst:
  dst.write(header)
  for name,offset,size,digest,flags in entries:
   key=(size,digest);record=unique.get(key);src.seek(base+offset)
   md5=hashlib.md5();sha=hashlib.sha256();remaining=size
   if record is None:
    dst.write(b'\0'*((-dst.tell())%16));new_offset=dst.tell()-112
   else:new_offset=record[0]
   while remaining:
    block=src.read(min(8*1024*1024,remaining))
    if not block:raise EOFError(name)
    remaining-=len(block);md5.update(block);sha.update(block)
    if record is None:dst.write(block)
   if md5.digest()!=digest:raise ValueError('Source checksum mismatch: '+repr(name))
   if record is not None and sha.digest()!=record[1]:raise ValueError('Checksum collision')
   unique[key]=(new_offset,sha.digest());mapped.append((name,new_offset,size,digest,flags))
  dst.write(b'\0'*((-dst.tell())%16));directory=dst.tell()
  dst.write(struct.pack('<I',len(mapped)))
  for name,offset,size,digest,flags in mapped:
   dst.write(struct.pack('<I',len(name))+name+struct.pack('<QQ',offset,size)+digest+flags)
  dst.seek(24);dst.write(struct.pack('<QQ',112,directory))
 # Read back every unique payload and every directory entry.
 _,new_base,check=read_directory(target)
 assert check==mapped
 verified=set()
 with target.open('rb') as f:
  for name,offset,size,digest,flags in check:
   if (offset,size) in verified:continue
   f.seek(new_base+offset);md5=hashlib.md5();remaining=size
   while remaining:
    block=f.read(min(8*1024*1024,remaining));assert block
    md5.update(block);remaining-=len(block)
   assert md5.digest()==digest,name
   verified.add((offset,size))
 result={'before_bytes':source.stat().st_size,'after_bytes':target.stat().st_size,'saved_bytes':source.stat().st_size-target.stat().st_size,'resource_paths':len(entries),'unique_payloads':len(unique)}
 print(json.dumps(result),flush=True)
 target.with_suffix('.dedup.json').write_text(json.dumps(result,indent=2))
if __name__=='__main__':main()
