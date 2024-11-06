import Dispatch
import Combine

typealias Envelope = (total: Int, results: [String])

func requestFromCursor(page: Int) -> AnyPublisher<Envelope, Never> {
    Deferred {
        Future { promise in
            promise(.success(Envelope(0, ["\(page)"])))
        }
    }
    .eraseToAnyPublisher()
}

let erratic = Just(()).delay(for: 0.0, tolerance: 0.001, scheduler: DispatchQueue.main).eraseToAnyPublisher()
    .merge(with: Just(()).delay(for: 1.0, tolerance: 0.001, scheduler: DispatchQueue.main).eraseToAnyPublisher())
    .merge(with: Just(()).delay(for: 2.0, tolerance: 0.001, scheduler: DispatchQueue.main).eraseToAnyPublisher())
    .merge(with: Just(()).delay(for: 3.0, tolerance: 0.001, scheduler: DispatchQueue.main).eraseToAnyPublisher())
    .merge(with: Just(()).delay(for: 4.0, tolerance: 0.001, scheduler: DispatchQueue.main).eraseToAnyPublisher())
    .merge(with: Just(()).delay(for: 5.0, tolerance: 0.001, scheduler: DispatchQueue.main).eraseToAnyPublisher())
    .handleEvents(receiveOutput: { print("scrollview bottom reached") })
    .makeConnectable()

var subscriptions = Set<AnyCancellable>()

func pagination<Value: Equatable, Envelope, ErrorEnvelope: Error>(
    requestNextPageWhen requestNextPage: AnyPublisher<Void, Never>,
    requestFromCursor: @escaping ((Int) -> AnyPublisher<Envelope, ErrorEnvelope>),
    valuesFromEnvelope: @escaping ((Envelope) -> [Value]),
    concator: @escaping (([Value], [Value]) -> [Value]) = (+)
) -> (
    isLoading: AnyPublisher<Bool, Never>,
    paginatedValues: AnyPublisher<[Value], ErrorEnvelope>,
    cursor: AnyPublisher<Int, Never>
) {
    let cursor = CurrentValueSubject<Int, Never>(0)
    let isLoading = CurrentValueSubject<Bool, Never>(false)
    let cursorOnNextPage = requestNextPage.combineLatest(cursor)
        .removeDuplicates(by: { $0.1 == $1.1 })
        .map(\.1)
    
    let paginatedValues = cursorOnNextPage.flatMap { page in
        requestFromCursor(page)
            .handleEvents(
                receiveOutput: { [weak cursor] _ in
                    cursor?.send((cursor?.value ?? 0) + 1)
                },
                receiveCompletion: { [weak isLoading] _ in
                    isLoading?.send(false)
                },
                receiveCancel: { [weak isLoading] in
                    isLoading?.send(false)
                },
                receiveRequest: { [weak isLoading] _ in
                    isLoading?.send(true)
                }
            )
            .map(valuesFromEnvelope)
    }
    .scan([], concator)
    
    return (
        isLoading.eraseToAnyPublisher(),
        paginatedValues.eraseToAnyPublisher(),
        cursor.eraseToAnyPublisher()
    )
}

let (isLoading, paginatedValues, cursor) = pagination(
    requestNextPageWhen: erratic.eraseToAnyPublisher(),
    requestFromCursor: { requestFromCursor(page: $0) },
    valuesFromEnvelope: { $0.results }
)

paginatedValues.sink {
    print("request from cursor result: \($0)")
}
.store(in: &subscriptions)

cursor.compactMap { $0 }
    .sink(receiveValue: { print("cursor emit: \($0)") })
    .store(in: &subscriptions)

isLoading.sink { loading in
    print("isLoading: \(loading)")
}
.store(in: &subscriptions)

/// Simulate scroll view reach bottom.
erratic.connect().store(in: &subscriptions)
