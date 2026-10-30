#ifndef STATS_SPAKE2_BRIDGE_H
#define STATS_SPAKE2_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

// The output buffer for each message must hold 33 bytes; the key buffer 32.
void *stats_spake2_start(uint8_t role, const uint8_t *code, size_t code_len,
                         uint8_t *message_out, size_t message_capacity);
int32_t stats_spake2_finish(void *state, const uint8_t *peer_message,
                            size_t peer_message_len, uint8_t *key_out,
                            size_t key_capacity);
void stats_spake2_free(void *state);

#endif
