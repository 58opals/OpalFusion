// MutableBoolBox.swift

actor MutableBoolBox {
    private var storedValue: Bool?

    func set(_ value: Bool) {
        storedValue = value
    }

    func value() -> Bool? {
        storedValue
    }
}
