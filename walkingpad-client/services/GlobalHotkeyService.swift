import Cocoa
import Carbon

class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()
    
    fileprivate var hotkeys: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    
    func setup(
        onUp: @escaping () -> Void,
        onDown: @escaping () -> Void,
        onUpCoarse: @escaping () -> Void,
        onDownCoarse: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onStats: @escaping () -> Void
    ) {
        registerHotkey(id: 1, keyCode: 126, modifiers: UInt32(cmdKey | optionKey), handler: onUp)
        registerHotkey(id: 2, keyCode: 125, modifiers: UInt32(cmdKey | optionKey), handler: onDown)
        registerHotkey(id: 3, keyCode: 126, modifiers: UInt32(cmdKey | optionKey | shiftKey), handler: onUpCoarse)
        registerHotkey(id: 4, keyCode: 125, modifiers: UInt32(cmdKey | optionKey | shiftKey), handler: onDownCoarse)
        registerHotkey(id: 5, keyCode: 49, modifiers: UInt32(cmdKey | optionKey), handler: onToggle)
        registerHotkey(id: 6, keyCode: 15, modifiers: UInt32(cmdKey | optionKey), handler: onReset)
        registerHotkey(id: 7, keyCode: 1, modifiers: UInt32(cmdKey | optionKey), handler: onStats)
        
        setupEventHandler()
    }
    
    private func registerHotkey(id: UInt32, keyCode: Int, modifiers: UInt32, handler: @escaping () -> Void) {
        var hotKeyRef: EventHotKeyRef?
        let signature = UTGetOSTypeFromString("WPAD" as CFString)
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status == noErr {
            hotkeys[id] = handler
        } else {
            appLog("Failed to register hotkey \(id): \(status)")
        }
    }
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamName(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if status == noErr {
                let id = hotKeyID.id
                if let handler = GlobalHotkeyService.shared.hotkeys[id] {
                    handler()
                    return noErr
                }
            }
            
            return CallNextEventHandler(nextHandler, event)
        }, 1, &eventType, nil, &eventHandler)
        
        if status != noErr {
            appLog("Failed to install event handler: \(status)")
        }
    }
}
