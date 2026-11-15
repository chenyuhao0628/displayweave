//
// Copyright (C) 2026 DisplayWeave contributors
// Adapted from OpenDisplay (https://github.com/OpenDisplay/OpenDisplay,
// commit bcf8e2b), Copyright (C) OpenDisplay contributors.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//

import Foundation

/// USB interface descriptors published by an Android composite gadget that can
/// speak Android Open Accessory (AOA) without disturbing non-Android peripherals.
///
/// Sending a vendor control request (`0xC0`, request 51 `GET_PROTOCOL`) to an
/// arbitrary attached USB device (such as an ASIX AX88179A USB-C dock Ethernet
/// controller) can wedge its control pipe and drop wired networking. Probing is
/// therefore restricted strictly to interfaces matched by this classifier.
enum AndroidUSBFunction: Equatable, Sendable {
    case adb
    case mtp

    /// `(bInterfaceClass, bInterfaceSubClass, bInterfaceProtocol)` tuples used
    /// for IOKit `IOUSBHostInterface` matching dictionaries.
    static let candidates: [(class: UInt8, subclass: UInt8, protocol: UInt8)] = [
        (0xFF, 0x42, 0x01), // Android ADB function (f_ffs)
        (0x06, 0x01, 0x01), // Still Image / MTP function (f_mtp)
        (0xFF, 0xFF, 0x00), // Vendor-specific f_mtp on Samsung / AOSP builds
    ]

    /// Classifies an interface from its USB triple and `iInterface` (`kUSBString`).
    init?(interfaceClass: UInt8, subclass: UInt8, protocol proto: UInt8, name: String?) {
        switch (interfaceClass, subclass, proto) {
        case (0xFF, 0x42, 0x01):
            self = .adb
        case (0x06, 0x01, 0x01), (0xFF, 0xFF, 0x00):
            // 0x06/0x01/0x01 is shared with PTP cameras and 0xFF/0xFF/0x00 is
            // shared with USB-C docks and the accessory interface itself; Linux
            // f_mtp sets iInterface to "MTP".
            guard name?.uppercased().contains("MTP") == true else { return nil }
            self = .mtp
        default:
            return nil
        }
    }
}
