// MutableBoolBox.swift

actor MutableBoolBox {
    private var storedValue: Bool?

    func update(_ value: Bool) {
        storedValue = value
    }

    func value() -> Bool? {
        storedValue
    }
}
