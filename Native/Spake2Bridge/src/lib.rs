use spake2::{Ed25519Group, Identity, Password, Spake2};
use std::ptr;

const PHONE_ID: &[u8] = b"StatsForIOS.Phone.v2";
const MAC_ID: &[u8] = b"StatsForIOS.Mac.v2";
const MESSAGE_LEN: usize = 33;
const KEY_LEN: usize = 32;

#[no_mangle]
pub unsafe extern "C" fn stats_spake2_start(
    role: u8,
    code: *const u8,
    code_len: usize,
    message_out: *mut u8,
    message_capacity: usize,
) -> *mut Spake2<Ed25519Group> {
    if code.is_null() || message_out.is_null() || code_len != 5 || message_capacity < MESSAGE_LEN {
        return ptr::null_mut();
    }
    let code = std::slice::from_raw_parts(code, code_len);
    if !code.iter().all(u8::is_ascii_digit) {
        return ptr::null_mut();
    }
    let password = Password::new(code);
    let phone = Identity::new(PHONE_ID);
    let mac = Identity::new(MAC_ID);
    let (state, message) = match role {
        0 => Spake2::<Ed25519Group>::start_a(&password, &phone, &mac),
        1 => Spake2::<Ed25519Group>::start_b(&password, &phone, &mac),
        _ => return ptr::null_mut(),
    };
    if message.len() != MESSAGE_LEN {
        return ptr::null_mut();
    }
    ptr::copy_nonoverlapping(message.as_ptr(), message_out, MESSAGE_LEN);
    Box::into_raw(Box::new(state))
}

#[no_mangle]
pub unsafe extern "C" fn stats_spake2_finish(
    state: *mut Spake2<Ed25519Group>,
    peer_message: *const u8,
    peer_message_len: usize,
    key_out: *mut u8,
    key_capacity: usize,
) -> i32 {
    if state.is_null() { return -1 }
    let state = *Box::from_raw(state);
    if peer_message.is_null() || key_out.is_null() || peer_message_len != MESSAGE_LEN || key_capacity < KEY_LEN {
        return -1;
    }
    let peer = std::slice::from_raw_parts(peer_message, peer_message_len);
    match state.finish(peer) {
        Ok(key) if key.len() == KEY_LEN => {
            ptr::copy_nonoverlapping(key.as_ptr(), key_out, KEY_LEN);
            0
        }
        _ => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn stats_spake2_free(state: *mut Spake2<Ed25519Group>) {
    if !state.is_null() {
        drop(Box::from_raw(state));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matching_code_derives_same_key() {
        let (phone, phone_message) = Spake2::<Ed25519Group>::start_a(
            &Password::new(b"47877"), &Identity::new(PHONE_ID), &Identity::new(MAC_ID));
        let (mac, mac_message) = Spake2::<Ed25519Group>::start_b(
            &Password::new(b"47877"), &Identity::new(PHONE_ID), &Identity::new(MAC_ID));
        assert_eq!(phone.finish(&mac_message).unwrap(), mac.finish(&phone_message).unwrap());
    }

    #[test]
    fn wrong_code_does_not_derive_same_key() {
        let (phone, phone_message) = Spake2::<Ed25519Group>::start_a(
            &Password::new(b"00000"), &Identity::new(PHONE_ID), &Identity::new(MAC_ID));
        let (mac, mac_message) = Spake2::<Ed25519Group>::start_b(
            &Password::new(b"47877"), &Identity::new(PHONE_ID), &Identity::new(MAC_ID));
        assert_ne!(phone.finish(&mac_message).unwrap(), mac.finish(&phone_message).unwrap());
    }
}
