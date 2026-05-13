// MutableBoolBox.swift

actor MutableBoolBox {
    private var storedValue: Bool?

    func update(_ value: Bool) {
        storedValue = value
    }

    var value: Bool? {
        storedValue
    }
}
