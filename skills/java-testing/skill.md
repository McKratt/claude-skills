---
name: java-testing
description: Use when writing, reviewing, or fixing Java tests — unit tests, slice tests, or integration tests
---

# Java Testing

## Stack

| Concern         | Library                                                               |
|-----------------|-----------------------------------------------------------------------|
| Test runner     | JUnit 6 (`@Test`, `@ExtendWith`, `@ParameterizedTest`)                |
| Assertions      | AssertJ (`assertThat(...)`)                                           |
| Mocking         | Mockito via BDD notation (`BDDMockito`)                               |
| HTTP stubbing   | WireMock                                                              |
| Spring slices   | Spring Boot 4 Test (`@WebMvcTest`, `@DataJpaTest`, `@SpringBootTest`) |
| Real containers | Testcontainers 2.0                                                    |

---

## Structure: Arrange / Act / Assert

Every test method follows AAA with explicit comments when the sections are non-trivial:

```java

@Test
void should_return_order_when_id_exists() {
    // Arrange
    var order = new Order("123", Status.PENDING);
    given(orderRepository.findById("123")).willReturn(Optional.of(order));

    // Act
    var result = orderService.findById("123");

    // Assert
    assertThat(result).isPresent();
    assertThat(result.get().getStatus()).isEqualTo(Status.PENDING);
}
```

---

## Unit Tests

### Class Setup

```java

@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @InjectMocks
    private OrderService orderService;
}
```

### BDD Mockito Notation

Always use `BDDMockito` static imports — never `Mockito.when` / `Mockito.verify`:

```java
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willThrow;
```

**Stubbing:**

```java
given(repository.findById("123")).

willReturn(Optional.of(entity));

given(repository.save(any(Order.class))).

willAnswer(i ->i.

getArgument(0));

willThrow(new DataAccessException("db down") {
}).

given(repository).

findById("x");
```

**Verification:**

```java
then(repository).

should().

save(any(Order.class));

then(repository).

should(never()).

delete(any());

then(repository).

shouldHaveNoMoreInteractions();
```

### AssertJ Assertions

Prefer specific assertions over `isEqualTo(true)`:

```java
// Collections
assertThat(results).

hasSize(2).

extracting(Order::getId).

containsExactly("1","2");

// Exceptions
assertThatThrownBy(() ->service.

findById(null))
        .

isInstanceOf(IllegalArgumentException .class)
    .

hasMessageContaining("id must not be null");

// Optional
assertThat(result).

isPresent().

contains(expectedOrder);

// Soft assertions (multiple failures in one test)
assertSoftly(softly ->{
        softly.

assertThat(order.getId()).

isEqualTo("123");
    softly.

assertThat(order.getStatus()).

isEqualTo(Status.PENDING);
});
```

---

## Spring Boot Slice Tests

Use the narrowest slice that covers the behavior under test.

### Controller Layer — `@WebMvcTest`

Spring Boot 4 introduces `RestTestClient` as the preferred alternative to `MockMvc` — it provides a fluent API and works
against both mock and real servers.

```java

@WebMvcTest(OrderController.class)
@AutoConfigureMockMvc
class OrderControllerTest {

    @Autowired
    private RestTestClient restTestClient;  // backed by MockMvc

    @MockBean
    private OrderService orderService;

    @Test
    void should_return_200_when_order_found() {
        // Arrange
        given(orderService.findById("123")).willReturn(Optional.of(new OrderDto("123")));

        // Act & Assert
        restTestClient.get().uri("/orders/123")
                .exchange()
                .expectStatus().isOk()
                .expectBody(OrderDto.class)
                .value(dto -> assertThat(dto.getId()).isEqualTo("123"));
    }
}
```

`MockMvc` is still available when needed; inject it explicitly alongside `RestTestClient`.

### Repository Layer — `@DataJpaTest`

```java

@DataJpaTest
class OrderRepositoryTest {

    @Autowired
    private OrderRepository repository;

    @Test
    void should_find_by_status() {
        // Arrange
        repository.save(new Order("1", Status.PENDING));
        repository.save(new Order("2", Status.SHIPPED));

        // Act
        var results = repository.findByStatus(Status.PENDING);

        // Assert
        assertThat(results).hasSize(1).extracting(Order::getId).containsExactly("1");
    }
}
```

---

## Testcontainers

Use for integration tests that need a real database, broker, or other infrastructure.

```java

@SpringBootTest
@Testcontainers
class OrderIntegrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");
}
```

Share a single container across a test class with `static @Container` to avoid restart overhead.

---

## WireMock

Use when testing code that makes outbound HTTP calls.

```java

@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@AutoConfigureWireMock(port = 0)
class PaymentClientTest {

    @Autowired
    private RestTestClient restTestClient;  // targets the running server automatically

    @Test
    void should_return_confirmed_when_payment_succeeds() {
        // Arrange
        stubFor(post(urlEqualTo("/payments"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"status\":\"CONFIRMED\"}")));

        // Act
        var result = paymentClient.charge("order-1", Money.of(100));

        // Assert
        assertThat(result.getStatus()).isEqualTo("CONFIRMED");
    }
}
```

For standalone WireMock (without Spring):

```java

@ExtendWith(WireMockExtension.class)
class PaymentClientTest {

    @RegisterExtension
    static WireMockExtension wm = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build();
}
```

---

## Naming

Test method names use `snake_case` following `should_<expected_behavior>_when_<condition>`:

```
should_return_order_when_id_exists
should_throw_not_found_exception_when_id_missing
should_send_email_when_order_is_shipped
```

Test class name mirrors the class under test: `OrderService` → `OrderServiceTest`.

---

## What NOT to Do

- Do not use `Mockito.when(...)` or `Mockito.verify(...)` — always use BDD notation
- Do not use `assertTrue(result != null)` — use AssertJ (`assertThat(result).isNotNull()`)
- Do not share mutable test state between test methods
- Do not use `@SpringBootTest` for a test that only needs `@WebMvcTest` or `@DataJpaTest`
- Do not use camelCase for test method names — always use snake_case
