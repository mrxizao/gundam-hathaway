"""Lossless PCK resource compression. Run deduplicate_pck.py first.
Usage: python optimize_pck_resources.py input.pck output.pck
Requires Python 3.14 or newer (compression.zstd). Input is never modified.
"""
from pathlib import Path
from compression import zstd
import sys,struct,hashlib,json,time,importlib.util
spec=importlib.util.spec_from_file_location('dedup',str(Path(__file__).with_name('deduplicate_pck.py')));d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
def recompress(b):
 if b[:4]!=b'RSCC':return b
 mode,block,total=struct.unpack_from('<III',b,4)
 if mode!=2:return b
 sizes=struct.unpack_from('<'+'I'*(total//block+1),b,16);at=16+len(sizes)*4;parts=[]
 for n in sizes:parts.append(zstd.decompress(b[at:at+n]));at+=n
 raw=b''.join(parts);assert len(raw)==total
 newblock=262144;chunks=[zstd.compress(raw[i:i+newblock],level=9) for i in range(0,total,newblock)]
 if total%newblock==0:chunks.append(zstd.compress(b'',level=9))
 packed=b'RSCC'+struct.pack('<III',2,newblock,total)+struct.pack('<'+'I'*len(chunks),*map(len,chunks))+b''.join(chunks)+b'RSCC'
 if len(packed)>=len(b):return b
 assert hashlib.sha256(b''.join(zstd.decompress(c) for c in chunks)).digest()==hashlib.sha256(raw).digest()
 return packed
source=Path(sys.argv[1]);target=Path(sys.argv[2])
if source.resolve()==target.resolve() or target.exists():raise ValueError('Output must be a new file')
target.parent.mkdir(parents=True,exist_ok=True)
header,base,entries=d.read_directory(source);mapped=[];seen={};saved=0;start=time.time()
with source.open('rb') as src,target.open('wb') as dst:
 dst.write(header)
 for name,offset,size,digest,flags in entries:
  key=(offset,size)
  if key in seen:
   no,ns,md=seen[key];mapped.append((name,no,ns,md,flags));continue
  src.seek(base+offset);b=src.read(size);assert hashlib.md5(b).digest()==digest
  new=recompress(b) if size>1024*1024 and name.rstrip(b'\0').endswith((b'.scn',b'.res')) else b
  if len(new)<size:
   saved+=size-len(new);print('RECOMPRESS',name.rstrip(b'\0').decode(),round((size-len(new))/1024**2,1),'MB; total',round(saved/1024**2,1),flush=True)
  dst.write(b'\0'*((-dst.tell())%16));no=dst.tell()-112;dst.write(new);md=hashlib.md5(new).digest();seen[key]=(no,len(new),md);mapped.append((name,no,len(new),md,flags))
 dst.write(b'\0'*((-dst.tell())%16));directory=dst.tell();dst.write(struct.pack('<I',len(mapped)))
 for name,offset,size,digest,flags in mapped:dst.write(struct.pack('<I',len(name))+name+struct.pack('<QQ',offset,size)+digest+flags)
 dst.seek(24);dst.write(struct.pack('<QQ',112,directory))
_,nb,check=d.read_directory(target);assert check==mapped
with target.open('rb') as f:
 for offset,size,md in seen.values():
  f.seek(nb+offset);assert hashlib.md5(f.read(size)).digest()==md
result={'before':source.stat().st_size,'after':target.stat().st_size,'saved':source.stat().st_size-target.stat().st_size,'paths':len(entries),'seconds':time.time()-start}
print('RESULT',json.dumps(result),flush=True);target.with_suffix('.optimization.json').write_text(json.dumps(result,indent=2))
