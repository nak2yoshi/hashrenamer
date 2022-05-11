import std.process    : executeShell;
import std.file       : isFile, isDir, dirEntries, SpanMode, exists, read, rename;
import std.regex      : regex, replaceAll;
import std.path       : extension, buildPath, filenameCmp, dirName, setExtension;
import std.stdio      : writeln;
import std.format     : format;
import std.typecons   : Tuple;
import std.digest.crc;
import std.string     : toLower;
import std.range      : tee, No, array, walkLength;
import std.algorithm  : each, filter;
// third party library
import progress.bar;

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



/// エントリーポイント
void main(string[] args)
{
    // 日本語Windowsのコンソール文字化け対策
    version(Windows)
    {
        import core.sys.windows.windows : GetConsoleOutputCP, SetConsoleOutputCP, CP_UTF8;
        const beforeCP = GetConsoleOutputCP();
        SetConsoleOutputCP( CP_UTF8 );  // or use "chcp 65001" instead
        scope(exit) SetConsoleOutputCP( beforeCP );
    }

    string[] message;
    scope(exit) {
        each!writeln(message);
        executeShell("pause");
    }

    /// 処理ファイル数、リネーム数、重複ファイル数を記録
    Tuple!(size_t, "target", size_t, "renamed", size_t, "duplicated") counter;

    /// ファイル名をハッシュ文字列にリネーム
    void tryRename(HashKind = CRC32)(string orgName)
    {
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
        debug message ~= format!"[org:] %s"(orgName);

        // 既にリネーム済みなら何もしない
        if ( ! filenameCmp(orgName, renName) )
            return;

        counter.target++;

        if (!renName.exists)
        {
            // ファイル名をリネーム
            orgName.rename(renName);
            message ~= format!"[ren:] %s"(renName);
            counter.renamed++;
        }
        else
        {
            message ~= format!"[dup:] %s"(orgName);
            // ダブってたら新しい方をゴミ箱へ移動
            auto old = cast(ubyte[])read(renName);
            if (old.toHashString!HashKind == hash)
            {
                orgName.moveToTrash;
                message ~= format!"[del:] %s"(orgName);
            }
            counter.duplicated++;
        }
    }

    if (args.length != 2 || ! args[1].isDir)
    {
        message ~= "フォルダをドラッグ＆ドロップしてください。";
        return;
    }

    //writeln("画像ファイルのチェックと、リネームを実行しています。");
    try
    {
        auto listdir = dirEntries(args[1], "*.{jpg,jpeg,png,gif,bmp}*", SpanMode.breadth)
            .filter!(f => f.isFile)
            .array;
        auto progress = new Bar;
        progress.message = () => "リネームを実行しています";
        progress.max = listdir.walkLength;
        progress.start();
        listdir.each!( (path) {
            tryRename(path);
            progress.next();
        } );
        progress.finish();
    }
    catch (Exception e)
    {
        message ~= e.msg;
        return;
    }

    if (counter.target > 0)
    {
        message ~= format!"対象となる画像ファイル数   : %8d"(counter.target);
        message ~= format!"リネームした画像ファイル数 : %8d"(counter.renamed);
        message ~= "--------";
        message ~= format!"重複していた画像ファイル数 : %8d"(counter.duplicated);
    }
    else
    {
        message ~= "画像ファイルが見つからないか、既にリネームされています。";
        message ~= "リネームされるのは、JPEG/PNG/GIF/BMPのファイルのみです。";
    }
}
