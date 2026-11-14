package app.opendisplay.android.protocol;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Pure-Java, host-testable consented external mouse/trackpad & hardware keyboard translator
 * for DisplayWeave {@code mac-input-v1}.
 * Matches {@code Shared/DesktopInputProtocol.swift} and {@code Mac/DesktopInputInjector.swift}
 * byte-for-byte, including session UUID validation, monotonic sequence numbering, modifier
 * key routing, and the 16-key concurrency cap.
 */
public final class AndroidDesktopInput {
    public static final String CAPABILITY = "mac-input-v1";
    public static final long MAX_SAFE_SEQUENCE = 9_007_199_254_740_991L;
    public static final int MAX_HELD_KEYS = 16;
    public static final double SCROLL_PIXELS_PER_TICK = 40.0;
    private static final long MULTI_CLICK_WINDOW_MS = 400L;
    private static final double MULTI_CLICK_MAX_DIST = 0.02;

    // DisplayWeave modifier bitmask (0..31) matching DesktopInputInjector.flags
    public static final int MOD_SHIFT = 1 << 0;
    public static final int MOD_CONTROL = 1 << 1;
    public static final int MOD_OPTION = 1 << 2;
    public static final int MOD_COMMAND = 1 << 3;
    public static final int MOD_CAPS_LOCK = 1 << 4;

    // Android InputDevice / MotionEvent / KeyEvent constants (pure-Java mirror)
    public static final int SOURCE_MOUSE = 8194;
    public static final int SOURCE_TOUCHPAD = 1048584;
    public static final int SOURCE_MOUSE_RELATIVE = 131076;

    public static final int TOOL_TYPE_MOUSE = 3;

    public static final int ACTION_DOWN = 0;
    public static final int ACTION_UP = 1;
    public static final int ACTION_MOVE = 2;
    public static final int ACTION_CANCEL = 3;
    public static final int ACTION_HOVER_MOVE = 7;
    public static final int ACTION_SCROLL = 8;
    public static final int ACTION_HOVER_ENTER = 9;
    public static final int ACTION_HOVER_EXIT = 10;
    public static final int ACTION_BUTTON_PRESS = 11;
    public static final int ACTION_BUTTON_RELEASE = 12;

    public static final int BUTTON_PRIMARY = 1;
    public static final int BUTTON_SECONDARY = 2;
    public static final int BUTTON_TERTIARY = 4;

    public static final int META_SHIFT_ON = 1;
    public static final int META_ALT_ON = 2;
    public static final int META_CTRL_ON = 4096;
    public static final int META_META_ON = 65536;
    public static final int META_CAPS_LOCK_ON = 1048576;

    // Android modifier keycodes
    public static final int KEYCODE_ALT_LEFT = 57;
    public static final int KEYCODE_ALT_RIGHT = 58;
    public static final int KEYCODE_SHIFT_LEFT = 59;
    public static final int KEYCODE_SHIFT_RIGHT = 60;
    public static final int KEYCODE_CTRL_LEFT = 113;
    public static final int KEYCODE_CTRL_RIGHT = 114;
    public static final int KEYCODE_CAPS_LOCK = 115;
    public static final int KEYCODE_META_LEFT = 117;
    public static final int KEYCODE_META_RIGHT = 118;
    public static final int KEYCODE_FUNCTION = 119;

    // Android system keys that must remain handled by Android OS
    private static final int KEYCODE_HOME = 3;
    private static final int KEYCODE_BACK = 4;
    private static final int KEYCODE_VOLUME_UP = 24;
    private static final int KEYCODE_VOLUME_DOWN = 25;
    private static final int KEYCODE_POWER = 26;
    private static final int KEYCODE_VOLUME_MUTE = 164;
    private static final int KEYCODE_APP_SWITCH = 187;

    private static final Pattern UUID_PATTERN = Pattern.compile(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
    private static final Pattern INPUT_SESSION_FIELD =
            Pattern.compile("\"inputSession\"\\s*:\\s*\"([^\"]*)\"");
    private static final Pattern INPUT_STATUS_FIELD =
            Pattern.compile("\"inputStatus\"\\s*:\\s*\"([^\"]*)\"");
    private static final Pattern INPUT_CAPS_ARRAY =
            Pattern.compile("\"inputCaps\"\\s*:\\s*\\[([^\\]]*)\\]");

    private static final Map<Integer, Integer> ANDROID_TO_MAC_KEYCODE;

    static {
        Map<Integer, Integer> map = new HashMap<>(128);
        // Letters A..Z -> kVK_ANSI_*
        map.put(29, 0x00); // A
        map.put(30, 0x0B); // B
        map.put(31, 0x08); // C
        map.put(32, 0x02); // D
        map.put(33, 0x0E); // E
        map.put(34, 0x03); // F
        map.put(35, 0x05); // G
        map.put(36, 0x04); // H
        map.put(37, 0x22); // I
        map.put(38, 0x26); // J
        map.put(39, 0x28); // K
        map.put(40, 0x25); // L
        map.put(41, 0x2E); // M
        map.put(42, 0x2D); // N
        map.put(43, 0x1F); // O
        map.put(44, 0x23); // P
        map.put(45, 0x0C); // Q
        map.put(46, 0x0F); // R
        map.put(47, 0x01); // S
        map.put(48, 0x11); // T
        map.put(49, 0x20); // U
        map.put(50, 0x09); // V
        map.put(51, 0x0D); // W
        map.put(52, 0x07); // X
        map.put(53, 0x10); // Y
        map.put(54, 0x06); // Z

        // Digits 0..9 -> kVK_ANSI_0..9
        map.put(7, 0x1D);  // 0
        map.put(8, 0x12);  // 1
        map.put(9, 0x13);  // 2
        map.put(10, 0x14); // 3
        map.put(11, 0x15); // 4
        map.put(12, 0x17); // 5
        map.put(13, 0x16); // 6
        map.put(14, 0x1A); // 7
        map.put(15, 0x1C); // 8
        map.put(16, 0x19); // 9

        // Punctuation & symbols
        map.put(69, 0x1B); // MINUS
        map.put(70, 0x18); // EQUALS
        map.put(71, 0x21); // LEFT_BRACKET
        map.put(72, 0x1E); // RIGHT_BRACKET
        map.put(73, 0x2A); // BACKSLASH
        map.put(74, 0x29); // SEMICOLON
        map.put(75, 0x27); // APOSTROPHE / QUOTE
        map.put(68, 0x32); // GRAVE
        map.put(55, 0x2B); // COMMA
        map.put(56, 0x2F); // PERIOD
        map.put(76, 0x2C); // SLASH

        // Editing & whitespace
        map.put(66, 0x24);  // ENTER -> kVK_Return
        map.put(61, 0x30);  // TAB -> kVK_Tab
        map.put(62, 0x31);  // SPACE -> kVK_Space
        map.put(67, 0x33);  // DEL (Backspace) -> kVK_Delete
        map.put(111, 0x35); // ESCAPE -> kVK_Escape
        map.put(112, 0x75); // FORWARD_DEL -> kVK_ForwardDelete
        map.put(124, 0x72); // INSERT -> kVK_Help
        map.put(259, 0x72); // HELP -> kVK_Help

        // Navigation & arrows
        map.put(21, 0x7B);  // DPAD_LEFT -> kVK_LeftArrow
        map.put(22, 0x7C);  // DPAD_RIGHT -> kVK_RightArrow
        map.put(20, 0x7D);  // DPAD_DOWN -> kVK_DownArrow
        map.put(19, 0x7E);  // DPAD_UP -> kVK_UpArrow
        map.put(122, 0x73); // MOVE_HOME -> kVK_Home
        map.put(123, 0x77); // MOVE_END -> kVK_End
        map.put(92, 0x74);  // PAGE_UP -> kVK_PageUp
        map.put(93, 0x79);  // PAGE_DOWN -> kVK_PageDown

        // Function keys F1..F20
        map.put(131, 0x7A); // F1
        map.put(132, 0x78); // F2
        map.put(133, 0x63); // F3
        map.put(134, 0x76); // F4
        map.put(135, 0x60); // F5
        map.put(136, 0x61); // F6
        map.put(137, 0x62); // F7
        map.put(138, 0x64); // F8
        map.put(139, 0x65); // F9
        map.put(140, 0x6D); // F10
        map.put(141, 0x67); // F11
        map.put(142, 0x6F); // F12
        map.put(326, 0x69); // F13
        map.put(327, 0x6B); // F14
        map.put(328, 0x71); // F15
        map.put(329, 0x6A); // F16
        map.put(330, 0x40); // F17
        map.put(331, 0x4F); // F18
        map.put(332, 0x50); // F19
        map.put(333, 0x5A); // F20

        // Keypad
        map.put(144, 0x52); // NUMPAD_0
        map.put(145, 0x53); // NUMPAD_1
        map.put(146, 0x54); // NUMPAD_2
        map.put(147, 0x55); // NUMPAD_3
        map.put(148, 0x56); // NUMPAD_4
        map.put(149, 0x57); // NUMPAD_5
        map.put(150, 0x58); // NUMPAD_6
        map.put(151, 0x59); // NUMPAD_7
        map.put(152, 0x5B); // NUMPAD_8 (0x5B = 91; 0x5A is kVK_F20!)
        map.put(153, 0x5C); // NUMPAD_9
        map.put(158, 0x41); // NUMPAD_DOT
        map.put(155, 0x43); // NUMPAD_MULTIPLY
        map.put(157, 0x45); // NUMPAD_ADD
        map.put(143, 0x47); // NUM_LOCK -> kVK_ANSI_KeypadClear
        map.put(154, 0x4B); // NUMPAD_DIVIDE
        map.put(160, 0x4C); // NUMPAD_ENTER
        map.put(156, 0x4E); // NUMPAD_SUBTRACT
        map.put(161, 0x51); // NUMPAD_EQUALS

        ANDROID_TO_MAC_KEYCODE = Collections.unmodifiableMap(map);
    }

    private String inputSession;
    private long sequence;
    private int heldButtonsMask;
    private int currentModifiers;
    private final Set<Integer> heldMacKeys = new HashSet<>();
    private int lastClickButton = -1;
    private int lastClickCount = 0;
    private long lastClickTimeMs = 0L;
    private double lastClickX = -1.0;
    private double lastClickY = -1.0;

    public static boolean isExternalPointer(int source, int toolType) {
        if (AndroidStylusInput.isStylusToolType(toolType)) {
            return false;
        }
        return toolType == TOOL_TYPE_MOUSE
                || (source & SOURCE_MOUSE) == SOURCE_MOUSE
                || (source & SOURCE_TOUCHPAD) == SOURCE_TOUCHPAD
                || (source & SOURCE_MOUSE_RELATIVE) == SOURCE_MOUSE_RELATIVE;
    }

    public static boolean isSystemReservedKey(int androidKeyCode) {
        return androidKeyCode == KEYCODE_HOME
                || androidKeyCode == KEYCODE_BACK
                || androidKeyCode == KEYCODE_VOLUME_UP
                || androidKeyCode == KEYCODE_VOLUME_DOWN
                || androidKeyCode == KEYCODE_VOLUME_MUTE
                || androidKeyCode == KEYCODE_POWER
                || androidKeyCode == KEYCODE_APP_SWITCH;
    }

    public static boolean isForbiddenMacModifierKeyCode(int macKeyCode) {
        return macKeyCode >= 54 && macKeyCode <= 63;
    }

    public static Integer mapAndroidKeyCodeToMac(int androidKeyCode) {
        Integer code = ANDROID_TO_MAC_KEYCODE.get(androidKeyCode);
        if (code == null || code < 0 || code > 127 || isForbiddenMacModifierKeyCode(code)) {
            return null;
        }
        return code;
    }

    public static int modifiersFromAndroidMetaState(int metaState) {
        int mods = 0;
        if ((metaState & META_SHIFT_ON) != 0) {
            mods |= MOD_SHIFT;
        }
        if ((metaState & META_CTRL_ON) != 0) {
            mods |= MOD_CONTROL;
        }
        if ((metaState & META_ALT_ON) != 0) {
            mods |= MOD_OPTION;
        }
        if ((metaState & META_META_ON) != 0) {
            mods |= MOD_COMMAND;
        }
        if ((metaState & META_CAPS_LOCK_ON) != 0) {
            mods |= MOD_CAPS_LOCK;
        }
        return mods & 0x1F;
    }

    public synchronized void reset() {
        inputSession = null;
        sequence = 0L;
        heldButtonsMask = 0;
        currentModifiers = 0;
        heldMacKeys.clear();
        lastClickButton = -1;
        lastClickCount = 0;
        lastClickTimeMs = 0L;
    }

    /**
     * Updates consented desktop input grant from a sender {@code inputConfig} message.
     * Ignores pencil-only {@code inputConfig} updates so stylus negotiation never revokes
     * an active desktop input grant.
     */
    public synchronized void configureFromInputConfig(boolean tlsEncrypted, String json) {
        if (json == null || !json.contains("\"inputConfig\"")) {
            return;
        }
        boolean hasPencilStatus = json.contains("\"pencilActionStatus\"");
        boolean hasInputStatus = json.contains("\"inputStatus\"");
        boolean hasInputSession = json.contains("\"inputSession\"");
        boolean mentionsMacCap = json.contains("\"" + CAPABILITY + "\"");
        if (hasPencilStatus && !hasInputStatus && !hasInputSession && !mentionsMacCap) {
            return;
        }

        Matcher capsMatcher = INPUT_CAPS_ARRAY.matcher(json);
        String capsBody = capsMatcher.find() ? capsMatcher.group(1) : "";
        boolean hasCap = capsBody.contains("\"" + CAPABILITY + "\"");
        String status = extractString(INPUT_STATUS_FIELD, json);
        String session = extractString(INPUT_SESSION_FIELD, json);
        boolean statusReady = status == null || status.isEmpty() || "ready".equals(status);

        if (tlsEncrypted
                && hasCap
                && statusReady
                && session != null
                && UUID_PATTERN.matcher(session).matches()) {
            if (!session.equals(inputSession)) {
                inputSession = session;
                sequence = 0L;
                heldButtonsMask = 0;
                currentModifiers = 0;
                heldMacKeys.clear();
                lastClickButton = -1;
                lastClickCount = 0;
                lastClickTimeMs = 0L;
            }
        } else {
            reset();
        }
    }

    public synchronized boolean isGranted() {
        return inputSession != null;
    }

    public synchronized String inputSession() {
        return inputSession;
    }

    /**
     * Translates an external mouse/trackpad pointer event into {@code desktopInput} JSON messages.
     */
    public synchronized List<String> onPointerEvent(
            int actionMasked,
            double xPx,
            double yPx,
            double viewWidth,
            double viewHeight,
            int buttonState,
            double hScroll,
            double vScroll,
            int metaState,
            long eventTimeMs) {
        if (inputSession == null || viewWidth <= 0.0 || viewHeight <= 0.0
                || !Double.isFinite(xPx) || !Double.isFinite(yPx)) {
            return Collections.emptyList();
        }
        double x = clamp(xPx / viewWidth, 0.0, 1.0);
        double y = clamp(yPx / viewHeight, 0.0, 1.0);
        int mods = modifiersFromAndroidMetaState(metaState);
        currentModifiers = mods;

        List<String> messages = new ArrayList<>(4);
        int mappedButtons = mapAndroidButtonMask(buttonState);
        if ((actionMasked == ACTION_DOWN || actionMasked == ACTION_MOVE) && mappedButtons == 0) {
            // External touchpads synthesizing tap-to-click may report ACTION_DOWN with buttonState=0.
            mappedButtons = 1;
        }
        if (actionMasked == ACTION_UP || actionMasked == ACTION_CANCEL) {
            mappedButtons = 0;
        }

        if (actionMasked == ACTION_CANCEL) {
            String rel = releaseAll();
            return rel == null ? Collections.emptyList() : Collections.singletonList(rel);
        }

        if (actionMasked == ACTION_SCROLL) {
            double dx = Double.isFinite(hScroll)
                    ? clamp(-hScroll * SCROLL_PIXELS_PER_TICK, -4096.0, 4096.0)
                    : 0.0;
            double dy = Double.isFinite(vScroll)
                    ? clamp(vScroll * SCROLL_PIXELS_PER_TICK, -4096.0, 4096.0)
                    : 0.0;
            if (Math.abs(dx) > 1e-6 || Math.abs(dy) > 1e-6) {
                String msg = encodeScroll(x, y, dx, dy, mods);
                if (msg != null) {
                    messages.add(msg);
                }
            }
            return messages;
        }

        // Emit button transitions before/instead of move
        int newlyPressed = mappedButtons & ~heldButtonsMask;
        int newlyReleased = heldButtonsMask & ~mappedButtons;
        for (int btn = 0; btn <= 2; btn++) {
            int bit = 1 << btn;
            if ((newlyPressed & bit) != 0) {
                int clicks = computeClickCount(btn, x, y, eventTimeMs);
                heldButtonsMask |= bit;
                String msg = encodeButton("buttonDown", x, y, btn, clicks, mods);
                if (msg != null) {
                    messages.add(msg);
                }
            }
        }
        for (int btn = 0; btn <= 2; btn++) {
            int bit = 1 << btn;
            if ((newlyReleased & bit) != 0) {
                int clicks = (btn == lastClickButton && lastClickCount >= 1) ? lastClickCount : 1;
                heldButtonsMask &= ~bit;
                String msg = encodeButton("buttonUp", x, y, btn, clicks, mods);
                if (msg != null) {
                    messages.add(msg);
                }
            }
        }

        if (actionMasked == ACTION_MOVE
                || actionMasked == ACTION_HOVER_MOVE
                || actionMasked == ACTION_HOVER_ENTER) {
            String msg = encodeMove(x, y, mods);
            if (msg != null) {
                messages.add(msg);
            }
        }
        return messages;
    }

    /**
     * Translates a hardware keyboard {@code onKeyDown} / {@code onKeyUp} event into a
     * {@code desktopInput} JSON message when desktop input is granted.
     * Returns {@code null} if not granted or if the key is unmapped/system-reserved.
     */
    public synchronized String onKeyEvent(
            boolean isDown, int androidKeyCode, int metaState, int repeatCount) {
        if (inputSession == null || isSystemReservedKey(androidKeyCode)) {
            return null;
        }
        int modifierBit = modifierBitForKeyCode(androidKeyCode);
        if (modifierBit != 0 || androidKeyCode == KEYCODE_FUNCTION) {
            int mods = modifiersFromAndroidMetaState(metaState);
            if (modifierBit != 0 && modifierBit != MOD_CAPS_LOCK) {
                if (isDown) {
                    mods |= modifierBit;
                } else {
                    mods &= ~modifierBit;
                }
            } else if (modifierBit == MOD_CAPS_LOCK && isDown) {
                mods = (metaState & META_CAPS_LOCK_ON) != 0
                        ? (mods | MOD_CAPS_LOCK)
                        : (mods ^ MOD_CAPS_LOCK);
            }
            mods &= 0x1F;
            if (mods == currentModifiers) {
                return null;
            }
            currentModifiers = mods;
            return encodeModifiers(mods);
        }

        Integer macKeyCode = mapAndroidKeyCodeToMac(androidKeyCode);
        if (macKeyCode == null) {
            return null;
        }
        int mods = modifiersFromAndroidMetaState(metaState);
        currentModifiers = mods;

        if (isDown) {
            boolean alreadyHeld = heldMacKeys.contains(macKeyCode);
            boolean repeating = repeatCount > 0 || alreadyHeld;
            if (!alreadyHeld && heldMacKeys.size() >= MAX_HELD_KEYS) {
                return null;
            }
            if (alreadyHeld && repeatCount <= 0) {
                return null;
            }
            heldMacKeys.add(macKeyCode);
            return encodeKey("keyDown", macKeyCode, mods, repeating);
        } else {
            if (!heldMacKeys.remove(macKeyCode)) {
                return null;
            }
            return encodeKey("keyUp", macKeyCode, mods, false);
        }
    }

    /** Releases all held keys, buttons, and modifiers on focus loss, pause, or teardown. */
    public synchronized String releaseAll() {
        if (inputSession == null) {
            return null;
        }
        boolean hadActiveState = !heldMacKeys.isEmpty()
                || heldButtonsMask != 0
                || currentModifiers != 0;
        heldMacKeys.clear();
        heldButtonsMask = 0;
        currentModifiers = 0;
        if (!hadActiveState) {
            return null;
        }
        long seq = nextSequenceOrRevoke();
        if (seq <= 0L) {
            return null;
        }
        return "{\"type\":\"desktopInput\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + seq
                + ",\"kind\":\"releaseAll\",\"modifiers\":0}";
    }

    private int computeClickCount(int button, double x, double y, long eventTimeMs) {
        long dt = eventTimeMs - lastClickTimeMs;
        double dx = x - lastClickX;
        double dy = y - lastClickY;
        if (button == lastClickButton
                && lastClickTimeMs > 0L
                && dt >= 0L && dt <= MULTI_CLICK_WINDOW_MS
                && Math.hypot(dx, dy) <= MULTI_CLICK_MAX_DIST) {
            lastClickCount = (lastClickCount % 3) + 1;
        } else {
            lastClickCount = 1;
        }
        lastClickButton = button;
        lastClickTimeMs = eventTimeMs;
        lastClickX = x;
        lastClickY = y;
        return lastClickCount;
    }

    private String encodeMove(double x, double y, int modifiers) {
        long seq = nextSequenceOrRevoke();
        if (seq <= 0L) {
            return null;
        }
        return "{\"type\":\"desktopInput\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + seq
                + ",\"kind\":\"move\""
                + ",\"x\":" + AndroidStylusInput.compactNumber(x)
                + ",\"y\":" + AndroidStylusInput.compactNumber(y)
                + ",\"modifiers\":" + (modifiers & 0x1F)
                + "}";
    }

    private String encodeButton(
            String kind, double x, double y, int button, int clicks, int modifiers) {
        long seq = nextSequenceOrRevoke();
        if (seq <= 0L) {
            return null;
        }
        int clampedButton = Math.max(0, Math.min(2, button));
        int clampedClicks = Math.max(1, Math.min(3, clicks));
        return "{\"type\":\"desktopInput\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + seq
                + ",\"kind\":\"" + kind + "\""
                + ",\"x\":" + AndroidStylusInput.compactNumber(x)
                + ",\"y\":" + AndroidStylusInput.compactNumber(y)
                + ",\"button\":" + clampedButton
                + ",\"clicks\":" + clampedClicks
                + ",\"modifiers\":" + (modifiers & 0x1F)
                + "}";
    }

    private String encodeScroll(double x, double y, double dx, double dy, int modifiers) {
        long seq = nextSequenceOrRevoke();
        if (seq <= 0L) {
            return null;
        }
        return "{\"type\":\"desktopInput\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + seq
                + ",\"kind\":\"scroll\""
                + ",\"x\":" + AndroidStylusInput.compactNumber(x)
                + ",\"y\":" + AndroidStylusInput.compactNumber(y)
                + ",\"dx\":" + AndroidStylusInput.compactNumber(dx)
                + ",\"dy\":" + AndroidStylusInput.compactNumber(dy)
                + ",\"modifiers\":" + (modifiers & 0x1F)
                + "}";
    }

    private String encodeKey(String kind, int macKeyCode, int modifiers, boolean repeating) {
        if (macKeyCode < 0 || macKeyCode > 127 || isForbiddenMacModifierKeyCode(macKeyCode)) {
            return null;
        }
        long seq = nextSequenceOrRevoke();
        if (seq <= 0L) {
            return null;
        }
        String base = "{\"type\":\"desktopInput\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + seq
                + ",\"kind\":\"" + kind + "\""
                + ",\"keyCode\":" + macKeyCode
                + ",\"modifiers\":" + (modifiers & 0x1F);
        if (repeating) {
            base += ",\"repeat\":true";
        }
        return base + "}";
    }

    private String encodeModifiers(int modifiers) {
        long seq = nextSequenceOrRevoke();
        if (seq <= 0L) {
            return null;
        }
        return "{\"type\":\"desktopInput\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + seq
                + ",\"kind\":\"modifiers\""
                + ",\"modifiers\":" + (modifiers & 0x1F)
                + "}";
    }

    private long nextSequenceOrRevoke() {
        if (inputSession == null || sequence >= MAX_SAFE_SEQUENCE) {
            reset();
            return -1L;
        }
        return ++sequence;
    }

    private static int mapAndroidButtonMask(int buttonState) {
        int mask = 0;
        if ((buttonState & BUTTON_PRIMARY) != 0) {
            mask |= (1 << 0);
        }
        if ((buttonState & BUTTON_SECONDARY) != 0) {
            mask |= (1 << 1);
        }
        if ((buttonState & BUTTON_TERTIARY) != 0) {
            mask |= (1 << 2);
        }
        return mask;
    }

    private static int modifierBitForKeyCode(int androidKeyCode) {
        switch (androidKeyCode) {
            case KEYCODE_SHIFT_LEFT:
            case KEYCODE_SHIFT_RIGHT:
                return MOD_SHIFT;
            case KEYCODE_CTRL_LEFT:
            case KEYCODE_CTRL_RIGHT:
                return MOD_CONTROL;
            case KEYCODE_ALT_LEFT:
            case KEYCODE_ALT_RIGHT:
                return MOD_OPTION;
            case KEYCODE_META_LEFT:
            case KEYCODE_META_RIGHT:
                return MOD_COMMAND;
            case KEYCODE_CAPS_LOCK:
                return MOD_CAPS_LOCK;
            default:
                return 0;
        }
    }

    private static String extractString(Pattern pattern, String json) {
        Matcher matcher = pattern.matcher(json);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }
}
