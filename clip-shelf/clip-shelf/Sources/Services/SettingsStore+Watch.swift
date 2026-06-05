//
//  SettingsStore+Watch.swift
//  clip-shelf
//
//  Created by Codex on 2026/06/04.
//

import Combine

extension SettingsStore {
    func watch(key: SettingKey) -> AnyPublisher<Void, Never> {
        keyChanges
            .filter { $0 == key }
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
