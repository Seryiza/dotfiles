#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <xkbcommon/xkbcommon.h>

struct letter {
    const char *key_name;
    const char *cyrillic_lower;
    const char *cyrillic_upper;
    const char *latin;
};

static const struct letter letters[] = {
    {"AB08", "Cyrillic_be", "Cyrillic_BE", "comma"},
    {"AB09", "Cyrillic_yu", "Cyrillic_YU", "period"},
    {"TLDE", "Cyrillic_io", "Cyrillic_IO", "grave"},
    {"AD11", "Cyrillic_ha", "Cyrillic_HA", "bracketleft"},
    {"AD12", "Cyrillic_hardsign", "Cyrillic_HARDSIGN", "bracketright"},
    {"AC10", "Cyrillic_zhe", "Cyrillic_ZHE", "semicolon"},
    {"AC11", "Cyrillic_e", "Cyrillic_E", "apostrophe"},
    {"AD01", "Cyrillic_shorti", "Cyrillic_SHORTI", "q"},
    {"AD02", "Cyrillic_tse", "Cyrillic_TSE", "w"},
    {"AD03", "Cyrillic_u", "Cyrillic_U", "e"},
    {"AD04", "Cyrillic_ka", "Cyrillic_KA", "r"},
    {"AD05", "Cyrillic_ie", "Cyrillic_IE", "t"},
    {"AD06", "Cyrillic_en", "Cyrillic_EN", "y"},
    {"AD07", "Cyrillic_ghe", "Cyrillic_GHE", "u"},
    {"AD08", "Cyrillic_sha", "Cyrillic_SHA", "i"},
    {"AD09", "Cyrillic_shcha", "Cyrillic_SHCHA", "o"},
    {"AD10", "Cyrillic_ze", "Cyrillic_ZE", "p"},
    {"AC01", "Cyrillic_ef", "Cyrillic_EF", "a"},
    {"AC02", "Cyrillic_yeru", "Cyrillic_YERU", "s"},
    {"AC03", "Cyrillic_ve", "Cyrillic_VE", "d"},
    {"AC04", "Cyrillic_a", "Cyrillic_A", "f"},
    {"AC05", "Cyrillic_pe", "Cyrillic_PE", "g"},
    {"AC06", "Cyrillic_er", "Cyrillic_ER", "h"},
    {"AC07", "Cyrillic_o", "Cyrillic_O", "j"},
    {"AC08", "Cyrillic_el", "Cyrillic_EL", "k"},
    {"AC09", "Cyrillic_de", "Cyrillic_DE", "l"},
    {"AB01", "Cyrillic_ya", "Cyrillic_YA", "z"},
    {"AB02", "Cyrillic_che", "Cyrillic_CHE", "x"},
    {"AB03", "Cyrillic_es", "Cyrillic_ES", "c"},
    {"AB04", "Cyrillic_em", "Cyrillic_EM", "v"},
    {"AB05", "Cyrillic_i", "Cyrillic_I", "b"},
    {"AB06", "Cyrillic_te", "Cyrillic_TE", "n"},
    {"AB07", "Cyrillic_softsign", "Cyrillic_SOFTSIGN", "m"},
};

static xkb_mod_mask_t mod_mask(struct xkb_keymap *keymap, const char *name)
{
    xkb_mod_index_t index = xkb_keymap_mod_get_index(keymap, name);
    if (index == XKB_MOD_INVALID || index >= 8 * sizeof(xkb_mod_mask_t)) {
        fprintf(stderr, "missing or unsupported modifier: %s\n", name);
        exit(1);
    }
    return (xkb_mod_mask_t)1 << index;
}

static void expect_symbol(
    struct xkb_state *state,
    struct xkb_keymap *keymap,
    const struct letter *letter,
    xkb_mod_mask_t modifiers,
    xkb_mod_mask_t preserved,
    const char *expected_name)
{
    xkb_keycode_t keycode = xkb_keymap_key_by_name(keymap, letter->key_name);
    xkb_keysym_t expected = xkb_keysym_from_name(
        expected_name, XKB_KEYSYM_NO_FLAGS);

    if (keycode == XKB_KEYCODE_INVALID || expected == XKB_KEY_NoSymbol) {
        fprintf(stderr, "invalid test data for %s / %s\n", letter->key_name,
                expected_name);
        exit(1);
    }

    xkb_state_update_mask(state, modifiers, 0, 0, 0, 0, 1);
    xkb_keysym_t actual = xkb_state_key_get_one_sym(state, keycode);
    if (actual != expected) {
        char actual_name[64] = {0};
        xkb_keysym_get_name(actual, actual_name, sizeof(actual_name));
        fprintf(stderr, "%s with mask 0x%x: expected %s, got %s\n",
                letter->key_name, modifiers, expected_name, actual_name);
        exit(1);
    }

    for (xkb_mod_index_t index = 0; index < xkb_keymap_num_mods(keymap); ++index) {
        xkb_mod_mask_t bit = (xkb_mod_mask_t)1 << index;
        if ((preserved & bit) != 0 &&
            xkb_state_mod_index_is_consumed2(
                state, keycode, index, XKB_CONSUMED_MODE_XKB) != 0) {
            fprintf(stderr, "%s consumed preserved modifier index %u\n",
                    letter->key_name, index);
            exit(1);
        }
    }
}

int main(void)
{
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (context == NULL) {
        fprintf(stderr, "failed to create XKB context\n");
        return 1;
    }

    const struct xkb_rule_names names = {
        .rules = "evdev",
        .model = "pc105",
        .layout = "us,ru",
        .variant = NULL,
        .options = "grp:ctrl_space_toggle,custom:types,custom:positional-latin-shortcuts",
    };
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(
        context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (keymap == NULL) {
        fprintf(stderr, "failed to compile custom XKB keymap\n");
        xkb_context_unref(context);
        return 1;
    }

    /* River forwards a serialized XKB v1 keymap to Wayland clients. Exercise
     * that wire-format round trip instead of testing only Channel's in-memory
     * keymap. */
    char *wire_keymap = xkb_keymap_get_as_string(
        keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    if (wire_keymap == NULL) {
        fprintf(stderr, "failed to serialize XKB keymap\n");
        return 1;
    }
    xkb_keymap_unref(keymap);
    keymap = xkb_keymap_new_from_string(
        context, wire_keymap, XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    free(wire_keymap);
    if (keymap == NULL) {
        fprintf(stderr, "failed to parse serialized XKB keymap\n");
        return 1;
    }

    struct xkb_state *state = xkb_state_new(keymap);
    if (state == NULL) {
        fprintf(stderr, "failed to create XKB state\n");
        xkb_keymap_unref(keymap);
        xkb_context_unref(context);
        return 1;
    }

    const xkb_mod_mask_t shift = mod_mask(keymap, XKB_MOD_NAME_SHIFT);
    const xkb_mod_mask_t control = mod_mask(keymap, XKB_MOD_NAME_CTRL);
    const xkb_mod_mask_t alt = mod_mask(keymap, "Mod1");
    const xkb_mod_mask_t super = mod_mask(keymap, "Mod4");
    const xkb_mod_mask_t altgr = mod_mask(keymap, "Mod5");
    const xkb_mod_mask_t shortcut = control | alt | super;

    /* The Group2 overlay must not assign its three-level type to Group1.
     * Doing so makes Ctrl+letter select an absent Level3 in the US symbols and
     * reaches Wayland clients as NoSymbol. */
    xkb_keycode_t us_c = xkb_keymap_key_by_name(keymap, "AB03");
    xkb_state_update_mask(state, control, 0, 0, 0, 0, 0);
    if (xkb_state_key_get_one_sym(state, us_c) != XKB_KEY_c) {
        fprintf(stderr, "US Ctrl+C does not produce keysym c\n");
        return 1;
    }

    for (size_t i = 0; i < sizeof(letters) / sizeof(letters[0]); ++i) {
        const struct letter *letter = &letters[i];
        expect_symbol(state, keymap, letter, 0, 0, letter->cyrillic_lower);
        expect_symbol(state, keymap, letter, shift, 0, letter->cyrillic_upper);
        expect_symbol(state, keymap, letter, super, super, letter->latin);
        expect_symbol(state, keymap, letter, control, control, letter->latin);
        expect_symbol(state, keymap, letter, shift | control,
                      shift | control, letter->latin);
        expect_symbol(state, keymap, letter, alt, alt, letter->latin);
        expect_symbol(state, keymap, letter, shift | alt,
                      shift | alt, letter->latin);
        expect_symbol(state, keymap, letter, shift | super,
                      shift | super, letter->latin);
        expect_symbol(state, keymap, letter, shortcut, shortcut, letter->latin);
        expect_symbol(state, keymap, letter, shift | shortcut,
                      shift | shortcut, letter->latin);
        expect_symbol(state, keymap, letter, altgr, 0, letter->cyrillic_lower);
        expect_symbol(state, keymap, letter, shift | altgr,
                      0, letter->cyrillic_upper);
    }

    xkb_state_unref(state);

    struct xkb_state *toggle_state = xkb_state_new(keymap);
    xkb_keycode_t control_key = xkb_keymap_key_by_name(keymap, "LCTL");
    xkb_keycode_t space_key = xkb_keymap_key_by_name(keymap, "SPCE");
    if (toggle_state == NULL || control_key == XKB_KEYCODE_INVALID ||
        space_key == XKB_KEYCODE_INVALID) {
        fprintf(stderr, "failed to prepare Ctrl+Space layout toggle test\n");
        return 1;
    }
    xkb_state_update_key(toggle_state, control_key, XKB_KEY_DOWN);
    xkb_state_update_key(toggle_state, space_key, XKB_KEY_DOWN);
    if (xkb_state_serialize_layout(toggle_state, XKB_STATE_LAYOUT_EFFECTIVE) != 1) {
        fprintf(stderr, "Ctrl+Space did not switch to the second layout\n");
        return 1;
    }
    xkb_state_unref(toggle_state);

    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    return 0;
}
