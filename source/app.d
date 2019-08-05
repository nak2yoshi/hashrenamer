import std.file       : isFile, isDir, dirEntries, SpanMode, exists, read, rename, remove;
import std.regex      : regex, matchFirst, replaceAll;
import std.path       : extension, buildPath, filenameCmp, dirName, setExtension;
import core.thread    : Thread, seconds;
import std.stdio      : writeln, writefln;
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
string toHashString(Hash)(ubyte[] data)
{
    return data
        .digest!Hash
        .toHexString!(Order.decreasing)
        .dup;
}


/// エントリーポイント
void main(string[] args)
{
    version(Windows)
    {
        import core.sys.windows.windows : SetConsoleOutputCP;
        import core.sys.windows.winnls : CP_UTF8;
        SetConsoleOutputCP( CP_UTF8 );  // or use "chcp 65001" instead
    }
    scope(exit) Thread.sleep(5.seconds);

    /// 処理ファイル数、リネーム数、重複ファイル数を記録
    Tuple!(size_t, "target", size_t, "renamed", size_t, "duplicated") counter;

    /// ファイル名をハッシュ文字列にリネーム
    void tryRename(Hash = CRC32)(string orgName)
    {
        // 画像ファイルのみが対象
        if (!orgName.isImageFile)
            return;

        // ファイル読み込み
        auto data = cast(ubyte[])read(orgName);
        auto hash = data.toHashString!Hash;
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
            // ダブってたら新しい方を削除
            auto old = cast(ubyte[])read(renName);
            if (old.toHashString!Hash == hash)
            {
                writeln("[del]: ", orgName);
                orgName.remove;
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
