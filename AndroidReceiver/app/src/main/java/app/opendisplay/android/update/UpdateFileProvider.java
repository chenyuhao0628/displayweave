package app.opendisplay.android.update;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

public final class UpdateFileProvider extends ContentProvider {
    public static final String AUTHORITY = "app.opendisplay.android.update-files";
    public static final String FILE_NAME = "DisplayWeave-update.apk";
    public static final String MIME_TYPE = "application/vnd.android.package-archive";

    public static Uri uri() {
        return new Uri.Builder().scheme("content").authority(AUTHORITY)
                .appendPath(FILE_NAME).build();
    }

    public static File updateDirectory(android.content.Context context) {
        File downloads = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (downloads == null) throw new IllegalStateException("External files unavailable");
        return new File(downloads, "updates");
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        requireUri(uri);
        return MIME_TYPE;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        File file;
        try {
            file = verifiedFile(uri);
        } catch (FileNotFoundException error) {
            throw new IllegalStateException(error.getMessage(), error);
        }
        String[] columns = projection == null
                ? new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}
                : projection;
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String column : columns) {
            if (OpenableColumns.DISPLAY_NAME.equals(column)) row.add(FILE_NAME);
            else if (OpenableColumns.SIZE.equals(column)) row.add(file.length());
            else row.add(null);
        }
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Update APK is read-only");
        return ParcelFileDescriptor.open(verifiedFile(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Update APK is read-only");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection,
                      String[] selectionArgs) {
        throw new UnsupportedOperationException("Update APK is read-only");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Update APK is read-only");
    }

    private File verifiedFile(Uri uri) throws FileNotFoundException {
        requireUri(uri);
        try {
            File directory = updateDirectory(providerContext()).getCanonicalFile();
            File file = new File(directory, FILE_NAME).getCanonicalFile();
            if (!directory.equals(file.getParentFile()) || !file.isFile()) {
                throw new FileNotFoundException("Verified update APK is unavailable");
            }
            return file;
        } catch (IOException error) {
            throw new FileNotFoundException("Unable to resolve update APK");
        }
    }

    private void requireUri(Uri uri) {
        if (!"content".equals(uri.getScheme())
                || !AUTHORITY.equals(uri.getAuthority())
                || uri.getPathSegments().size() != 1
                || !FILE_NAME.equals(uri.getLastPathSegment())) {
            throw new IllegalArgumentException("Unsupported update URI");
        }
    }

    private android.content.Context providerContext() throws FileNotFoundException {
        android.content.Context context = getContext();
        if (context == null) throw new FileNotFoundException("Provider context unavailable");
        return context;
    }
}
