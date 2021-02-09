import tables, strutils, os, osproc, streams, parsecfg, options, json, times
import docopt, neverwinter/compressedbuf, neverwinter/resref, neverwinter/restype, tiny_sqlite
import reimplLibs

let args = docopt"""
Takes an nwsync .origin file and reconstructs the hak list accordingly.
Creates folders of hak contents, and then haks of those folders.
Note that all contents of outputDir not in the .origin will be removed.

Can create from server nwsync repo or from clients who have previously
downloaded the manifest.

Usage:
  nwsync_originate <origin> <outputDir> [options]
  nwsync_originate -h | --help
  nwsync_originate --version

Options:
  -a NWN_INI  Path to nwn.ini to find Alias for /hak, /tlk and /nwsync as
              required (see below)

  -d          Flag for .hak and .tlk to be placed in their alias Directory.
              Else places haks in outputDir. Requires -a switch.

  -c          By default, we attempt to re-originate from a server nwsync
              repo. This flag attempts from the client /nwsync which must have
              previously downloaded the same origin manifest. Requires -a
              switch
"""
#Adapted from nwsync --version handling
if args["--version"]:
  const nimble: string    = slurp(currentSourcePath().splitFile().dir & "/../nwsync_originate.nimble")
  const gitBranch: string = staticExec("git symbolic-ref -q --short HEAD").strip
  const gitRev: string    = staticExec("git rev-parse HEAD").strip

  let nimbleConfig   = loadConfig(newStringStream(nimble))
  let packageVersion = nimbleConfig.getSectionValue("", "version")
  let versionString  = "NWNT " & packageVersion & " (" & gitBranch & "/" & gitRev[0..5] & ", nim " & NimVersion & ")"

  echo versionString
  quit(0)

#read origins file into table(resref:hak)
var
  resHakMap = initTable[string, string]()
  hakList: seq[string]

let origin = $args["<origin>"]
let iniPath = if args["-a"]: $args["-a"] else: ""
let fromClient = args["-c"]
let outdir = $args["<outputDir>"]
let toAlias = args["-d"]
let nwnerfPath = findExe("nwn_erf")

if nwnerfPath == "":
  echo "Unable to find nwn_erf in PATH or running directory. Please ensure neverwinter.nim tools are available (See github readme)"
  echo "You are able to continue to extract to folders in OutDir, but no Haks will be created - Do you wish to continue? Y/N"
  let response = readline(stdin)
  if response.toLowerAscii() != "y":
    quit(0)

var #doc folders, with defaults for server/no-alias
  hakDir = outdir
  tlkDir = outdir
  nwsyncDir = outdir #unused without alias, but nonetheless..

if fromClient or toAlias:
  if iniPath == "" or iniPath.extractFilename() != "nwn.ini":
    echo "-a NWN_INI must be provided in order to use alias."
    quit(0)
  let ini = iniPath.openFileStream(fmRead)
  for line in ini.lines():
    if line[0..2] == "HAK" and toAlias:
      hakDir = line[4..^1]
    elif line[0..2] == "TLK" and toAlias:
      tlkDir = line[4..^1]
    elif line[0..5] == "NWSYNC" and fromClient:
      nwsyncDir = line[7..^1]
  ini.close()

proc readOrigins(path: string) =
  echo "reading origin file"
  var lastHak: string
  for line in path.lines():
    if line.len == 0: continue
    elif line.startsWith("Erf:"): #if a hak
      let hakname = line[4..^1].extractFilename()
      lastHak = hakname
      hakList.add(hakname)
    elif line.startsWith("\t"): #an entry
      resHakMap[line[1..^1].toLowerAscii()] = lastHak
      if line.len > 12 and line[1..10] == "__erfdup__":
        echo "Original name cannot be recoved for duplicate: " & line[1..^1].toLowerAscii() & ". Recommend de-duplicate in original repo"
    else: #tlk, maybe something else?
      lastHak = "ResFiles"

origin.readOrigins()

#Now we know contents, delete unused hak folders and res files
echo "Clean-up of unused Directories and Files"
proc clearDirectories(outdir: string) =
  var marked = newSeq[string]()

  for dir in outdir.walkDirRec({pcDir}, {}):
    let folder = dir.lastPathPart()[0..^3]
    if not hakList.contains(folder) and folder != "ResFiles":
      marked.add(dir)

  for dir in marked:
    dir.removeDir()

outdir.clearDirectories()

proc cleanFiles(outdir: string) =
  var marked = newSeq[string]()

  for file in outdir.walkDirRec({pcFile}, {pcDir}):
    let name = file.extractFilename()
    if not resHakMap.hasKey(name) and name != "hashfile.json":
      marked.add(file)

  for file in marked:
    file.removeFile()

outdir.cleanFiles()

#load existing json hashfile
var
  jHash = newJObject()
  jsonEx: bool
  jTime: Time
  fileTime = getTime()
if fileExists(outdir / "hashfile.json"):
  echo "Found existing hashfile"
  jHash = parseFile(outdir / "hashfile.json")
  jsonEx = true
  let getTime = jHash["WriteTime"].getStr()
  jTime = parseTime(getTime, "yyyy-MM-dd'T'HH:mm:sszzz", local())

#returns True if we don't need to redo this file.
proc checkRewrite(folder, resref, sha1: string): bool =
  if jsonEx and fileExists(folder / resRef):
    if ((folder / resRef).getLastModificationTime() - jTime).abs() < initDuration(seconds = 1):
      let hash = jHash.getOrDefault(resRef).getStr()
      if sha1 == hash:
        (folder / resRef).setLastModificationTime(fileTime)
        result = true

proc writeDecompressed(o: Stream, i: Stream|string): int =
  var data = ""
  try:
    data = i.decompress(makeMagic("NSYC"))
  except ValueError:
    if getCurrentExceptionMsg() == "payload size is zero":
      result = 1 #arbitrary return code for no payload.
    else: raise
  except: raise
  o.write(data)

#extract files when starting from a server repo
proc originateFromServer(originPath, outDir: string) =
  echo "Extracting files from the server NWSync repository. This may take some time."
  let manifest = readManifest(originPath.changeFileExt(""))

  #Read through manifests, finding resrefs and allocating them to folders
  var zeroSized: int
  for mfCount, mfEntry in manifest.entries:
    #first, get the hak set-up
    let resRef = $mfEntry.resRef.resolve().get() #ie abc.mdl
    let hakFolder = outDir / resHakMap[resRef] & "_f"
    discard existsOrCreateDir(hakFolder)
    if checkRewrite(hakFolder, resref, mfEntry.sha1):
      continue

    #now find the relevent file based on mfEntry.sha1
    let resStream = openFileStream(hakFolder / resRef, fmWrite)
    let repoPath = manifest.pathForEntry(originPath.parentDir().parentDir(), mfEntry.sha1, false)
    let dataStream = repoPath.openFileStream(fmRead)
    zeroSized += resStream.writeDecompressed(dataStream)
    resStream.close()
    (hakFolder / resRef).setLastModificationTime(fileTime)
    dataStream.close()
    jHash[resRef] = %mfentry.sha1

  if zeroSized > 0:
    echo $zeroSized & " zero-sized resources were written. Review whether this is intentional."

proc originateFromClient(originPath, nwsyncDir, outDir: string) =
  echo "Extracting files from the client NWSync repository"
  let metadb = openDatabase(nwsyncDir / "nwsyncmeta.sqlite3")
  #check they have the right manifest at all!
  let originsha1 = originPath.splitFile().name
  var hasOrigin: bool
  for row in metadb.rows("SELECT sha1 FROM manifests"):
    if originsha1 == row[0].fromDbValue(string):
      hasOrigin = true
      break

  if not hasOrigin:
    echo "The client NWSync repository does not have this origin. Terminating"
    quit(0)

  #map all sha1's to shards
  echo "Mapping nwsync shards"
  var shardID = newseq[int]()
  for row in metadb.rows("SELECT id FROM shards"):
    shardID.add(row[0].fromDbValue(int) - 1)

  var sha1Shard = initTable[string, int]()
  for i in shardID:
    let shard = openDatabase(nwsyncDir / "nwsyncdata_" & $i & ".sqlite3")
    for row in shard.rows("SELECT sha1 FROM resrefs"):
      sha1Shard[row[0].fromDbValue(string)] = i
    shard.close()

  #now to business matching sha1-resref-blob
  echo "Decompressing new files from Shards to outDir - This can take a while"
  var zeroSized: int
  for row in metadb.rows("SELECT resref_sha1, resref, restype FROM manifest_resrefs WHERE manifest_sha1 = ?", originsha1):
    let resSha1 = row[0].fromDbValue(string)
    let dbresref = row[1].fromDbValue(string)
    let dbrestype = row[2].fromDbValue(int).ResType
    let resRef = dbresref & "." & getResExt(dbrestype)

    let hakFolder = outDir / resHakMap[resRef] & "_f" #just the hak name, not folder. might need to reduce this i.e. without .hak at the end.
    discard existsOrCreateDir(hakFolder) #create the folder if its not there already.
    if checkRewrite(hakFolder, resRef, resSha1):
      continue
    let shard = openDatabase(nwsyncDir / "nwsyncdata_" & $sha1Shard[resSha1] & ".sqlite3")
    let blob = fromDbValue(shard.rows("SELECT data FROM resrefs WHERE sha1 = ?", resSha1)[0][0], seq[byte]).toString()
    let resStream = openFileStream(hakFolder / resRef, fmWrite) #check path here includes hakFolder

    zeroSized += resStream.writeDecompressed(blob)
    resStream.close()
    (hakFolder / resRef).setLastModificationTime(fileTime)
    shard.close()
    jHash[resRef] = %resSha1

  if zeroSized > 0:
    echo $zeroSized & " zero-sized resources were written. Review whether this is intentional."

if fromClient:
  origin.originateFromClient(nwsyncDir, outdir)
else:
  origin.originateFromServer(outdir)

#write out Json file
echo "Writing hashfile Json"
jHash["WriteTime"] = %($filetime)
let jsonFile = openFileStream(outdir / "hashfile.json", fmWrite)
jsonFile.write($jHash)
jsonFile.close()


proc hakPacker() =
  #all entries now written out, we're going to straight-up call the hak-making-thingo on the folders
  for packhak in hakList:
    echo "Packing with: -f " & hakDir / packhak & " -c " & outDir / packhak & "_f"
    let packer = startProcess(nwnerfPath, "", @["-f", hakDir / packhak, "-c", outDir / packhak & "_f"], nil, {poStdErrToStdOut, poUsePath})

    while packer.running:
      for line in packer.outputStream().lines:
        echo line

    if packer.waitForExit != 0:
      echo "Packing of " & packhak & " failed."

  if toAlias:
    for kind, file in walkdir(outDir / "ResFiles_f"):
      if file.splitFile().ext == ".tlk":
        file.copyFileToDir(tlkDir)
      else:
        echo "File alias directory for " & file.extractFilename & " is not yet coded. Please raise a github issue for this."

if nwnerfPath != "":
  hakPacker()
