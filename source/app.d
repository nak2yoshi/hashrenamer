import std.file       : isFile, isDir, dirEntries, SpanMode, exists, read, rename, remove;
import std.regex      : regex, matchFirst, replaceAll;
import std.path       : extension, buildPath, filenameCmp, dirName, setExtension;
import core.thread    : Thread, seconds;
version(Windows) {} else { import std.stdio; }
import std.typecons   : Tuple;
import std.digest     : toHexString, Digest;
import std.digest.crc;
import std.string     : toLower;
import std.range      : tee, No;
import std.algorithm  : each;

/// 画像ファイルか拡張子でチェック
bool isImageFile(string name)
{
    return name.isFile && !matchFirst(
        name.extension,
        regex(`^\.(jpe?g|png|gif|bmp)`, "i")
    ).empty;
}

/// データからハッシュ文字列を計算
string toHashString(HashKind)(ubyte[] data)
{
    return data
        .digest!HashKind
        .toHexString!(Order.decreasing)
        .dup;
}

/// ファイルをゴミ箱に移動
void moveToTrash(scope string name) @trusted
{
    version(Windows) {
        import core.sys.windows.shellapi;
        import std.path : isValidPath, absolutePath;
        import std.file : exists, FileException;
        import std.utf : toUTF16;

        if (!name.isValidPath || !name.exists) {
            throw new FileException(name);
        }
        const path = name.absolutePath();

        SHFILEOPSTRUCTW fileOp;
        fileOp.wFunc = FO_DELETE;
        fileOp.fFlags = FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_NOCONFIRMMKDIR | FOF_ALLOWUNDO;
        //Note: pFrom.typeof is PCZZTSTR
        //      This string must be double-null terminated.
        //https://docs.microsoft.com/en-us/windows/win32/api/shellapi/ns-shellapi-shfileopstructw
        wstring wPath = (path ~ "\0\0").toUTF16();
        fileOp.pFrom = wPath.ptr;
        int result = SHFileOperation(&fileOp);
        if (result != 0) {
            throw new FileException(path);
        }
    } else {
        assert(false, "Sorry, windows only");
    }
}

// 日本語Windowsのコンソール文字化け対策
version(Windows)
{
    import std.conv            : text;
    import std.format          : format;
    import std.stdio           : printf, puts;
    import std.functional      : forward;
    import std.windows.charset : toMBSz;

    template writeImpl(alias fn1, alias fn2)
    {
        void writeImpl(A...)(auto ref A args)
        {
            fn2(fn1(forward!args).toMBSz);
        }
    }
    alias write    = writeImpl!(text,   printf);
    alias writef   = writeImpl!(format, printf);
    alias writeln  = writeImpl!(text,   puts  );
    alias writefln = writeImpl!(format, puts  );
}


/// エントリーポイント
void main(string[] args)
{
    scope(exit) Thread.sleep(5.seconds);

    /// 処理ファイル数、リネーム数、重複ファイル数を記録
    Tuple!(size_t, "target", size_t, "renamed", size_t, "duplicated") counter;

    /// ファイル名をハッシュ文字列にリネーム
    void tryRename(HashKind = CRC32)(string orgName)
    {
        // 画像ファイルのみが対象
        if (!orgName.isImageFile)
            return;

        // ファイル読み込み
        auto data = cast(ubyte[])read(orgName);
        auto hash = data.toHashString!HashKind;
        // 拡張子の末尾(large|orig)対策
        auto ext = replaceAll(
            orgName.extension,
            regex(`^\.(jpe?g|png|gif|bmp).*$`, "i"),
            ".$1"
        );
        // ファイル名のみ、ハッシュ文字列に置き換える
        auto renName = buildPath(
            orgName.dirName,
            setExtension(hash, ext.toLower)
        );
        debug writeln("[org]: ", orgName);
        debug writeln("[ren]: ", renName);

        // 既にリネーム済みなら何もしない
        if (!filenameCmp(orgName, renName))
            return;

        counter.target++;

        if (!renName.exists)
        {
            // ファイル名をリネーム
            orgName.rename(renName);
            counter.renamed++;
        }
        else
        {
            writeln("[dup]: ", orgName);
            // ダブってたら新しい方をゴミ箱へ移動
            auto old = cast(ubyte[])read(renName);
            if (old.toHashString!HashKind == hash)
            {
                writeln("[del]: ", orgName);
                //orgName.remove;
                orgName.moveToTrash;
            }
            counter.duplicated++;
        }
    }

    if (args.length < 2)
    {
        writeln("ファイル/フォルダをドラッグ＆ドロップしてください。");
        return;
    }

    writeln("画像ファイルのチェックと、リネームを実行しています。");
    try
    {
        args[1 .. $]
            .tee!(path => path.isDir ? writeln(path) : 0, No.pipeOnPop)
            .each!(path => path.isDir
                ? path.dirEntries(SpanMode.breadth)
                    .tee!(path => path.isDir ? writeln(path) : 0, No.pipeOnPop)
                    .each!(path => tryRename(path))
                : tryRename(path));
    }
    catch (Exception e)
    {
        writeln(e.msg);
    }

    if (counter.target > 0)
    {
        writefln("対象となる画像ファイル数   : %8d", counter.target);
        writefln("リネームした画像ファイル数 : %8d", counter.renamed);
        writefln("--------");
        writefln("重複していた画像ファイル数 : %8d", counter.duplicated);
    }
    else
    {
        writeln("画像ファイルが見つからないか、既にリネームされています。");
        writeln("リネームされるのは、Jpeg/Png/Gif/Bmp ファイルのみです。");
    }
}
