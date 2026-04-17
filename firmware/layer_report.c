#include "raw_hid.h"
#include "action_layer.h"

#define LAYER_QUERY_CMD 0x42

// Called by Vial for any raw HID command it doesn't handle itself.
// Responds to LAYER_QUERY_CMD with the index of the currently active layer.
void raw_hid_receive_kb(uint8_t *data, uint8_t length) {
    if (data[0] != LAYER_QUERY_CMD) return;
    // via.c calls raw_hid_send() after this returns — do not call it here.
    data[0] = get_highest_layer(layer_state);
}
