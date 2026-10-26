package app.opendisplay.android;

import android.content.Context;
import android.view.SurfaceView;

/** Touch handlers call performClick after release so accessibility gets the event. */
public final class ReceiverSurfaceView extends SurfaceView {
    public ReceiverSurfaceView(Context context) { super(context); }
    @Override public boolean performClick() {
        super.performClick();
        return true;
    }
}
