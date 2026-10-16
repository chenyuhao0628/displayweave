package app.opendisplay.android;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.widget.Button;
import android.widget.LinearLayout;
import android.content.res.ColorStateList;
import android.widget.TextView;

/** Native receiver styling. Video surfaces intentionally retain a black background. */
final class ReceiverUi {
    private final Context context;
    final int background;
    final int surface;
    final int primary;
    final int secondary;
    final int accent;

    ReceiverUi(Context context) {
        this.context = context;
        boolean dark = (context.getResources().getConfiguration().uiMode
                & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        background = dark ? 0xFF111820 : 0xFFF5F7FA;
        surface = dark ? 0xFF202C38 : 0xFFFFFFFF;
        primary = dark ? 0xFFF0F5FA : 0xFF172433;
        accent = dark ? 0xFF9CCAFF : 0xFF185EA8;
        secondary = dark ? 0xFFB4C4D3 : 0xFF526375;
    }

    int dp(int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    TextView text(String value, int sp, int color, boolean bold) {
        TextView view = new TextView(context);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT_BOLD);
        return view;
    }

    Button button(String label) {
        Button button = new Button(context);
        button.setText(label);
        button.setAllCaps(false);
        button.setMinHeight(dp(48));
        return button;
    }


    Button primaryButton(String label) {
        Button button = button(label);
        button.setBackgroundTintList(ColorStateList.valueOf(accent));
        boolean dark = (context.getResources().getConfiguration().uiMode
                & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        button.setTextColor(dark ? 0xFF10243A : 0xFFFFFFFF);
        return button;
    }

    TextView heading(String value) {
        TextView view = text(value, 16, primary, true);
        view.setPadding(0, dp(24), 0, dp(8));
        if (android.os.Build.VERSION.SDK_INT >= 28) view.setAccessibilityHeading(true);
        return view;
    }

    LinearLayout panel() {
        LinearLayout panel = new LinearLayout(context);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(20), dp(16), dp(20), dp(16));
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(surface); shape.setCornerRadius(dp(16));
        panel.setBackground(shape);
        return panel;
    }

    void step(LinearLayout panel, int number, String title, String detail) {
        TextView heading = text(number + "  " + title, 16, primary, true);
        heading.setPadding(0, number == 1 ? 0 : dp(16), 0, dp(4));
        panel.addView(heading);
        TextView body = text(detail, 14, secondary, false);
        body.setLineSpacing(dp(3), 1.0f);
        panel.addView(body);
    }

    TextView card(String value) {
        TextView view = text(value, 16, primary, false);
        view.setLineSpacing(dp(4), 1.0f);
        view.setPadding(dp(20), dp(16), dp(20), dp(16));
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(surface);
        shape.setCornerRadius(dp(16));
        view.setBackground(shape);
        return view;
    }
}
