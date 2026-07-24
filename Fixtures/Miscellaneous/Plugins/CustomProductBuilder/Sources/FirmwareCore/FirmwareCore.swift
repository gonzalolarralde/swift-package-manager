import FirmwareC

public func firmwareEntryPoint() -> Int {
    Int(firmware_board_identifier())
}
