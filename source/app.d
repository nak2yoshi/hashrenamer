///dmd2.068.0
import std.file;
import std.datetime   : SysTime;
import std.regex      : regex, matchFirst, replaceAll;
import std.path       : extension, buildPath, filenameCmp, dirName, setExtension;
import core.thread;
import std.typecons   : Tuple;
import std.digest.crc;
import std.string     : toLower;

/// 画像ファイルか拡張子でチェック
bool isImage(string name)
{
    return name.isFile && !matchFirst(
        name.extension,
        regex(`^\.(jpe?g|png|gif|bmp)`, "i")
    ).empty;
}

/// データからハッシュ文字列を計算
string toHash(Hash)(ubyte[] data)
{
    return data
        .digest!Hash
        .toHexString!(Order.decreasing)
        .dup;
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
    void tryRename(string org)
    {
        // ファイル読み込み
        auto data = cast(ubyte[])read(org);
        // 拡張子の末尾(large|orig)対策
        auto ext = replaceAll(
            org.extension,
            regex(`^\.(jpe?g|png|gif|bmp).*$`, "i"),
            ".$1"
        );
        // ファイル名のみ、ハッシュ文字列に置き換える
        auto ren = buildPath(
            org.dirName,
            setExtension(data.toHash!CRC32, ext.toLower)
        );
        debug writeln("[org]: ", org);
        debug writeln("[ren]: ", ren);

        // 既にリネーム済みなら何もしない
        if (!filenameCmp(org, ren))
            return;

        counter.target++;

        if (!ren.exists)
        {
            // ファイル名をリネーム
            rename(org, ren);
            counter.renamed++;
        }
        else
        {
            debug writeln("[dup]: ", org);
            // ダブってたら新しい方を削除
            Tuple!(SysTime, "accessTime", SysTime, "modificationTime") otimes, rtimes;
            org.getTimes(otimes.accessTime, otimes.modificationTime);
            ren.getTimes(rtimes.accessTime, rtimes.modificationTime);
            if (otimes.modificationTime < rtimes.modificationTime)
            {
                ren.remove;
            }
            else
            {
                org.remove;
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
        foreach (arg; args)
        {
            if (arg.isDir)
            {
                writeln(arg);
                foreach ( path; dirEntries(arg, SpanMode.breadth) )
                {
                    if (path.isDir)
                        writeln(path);
                    else if (path.isImage)
                        tryRename(path);
                }
            }
            else if (arg.isImage)
            {
                tryRename(arg);
            }
        }
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
