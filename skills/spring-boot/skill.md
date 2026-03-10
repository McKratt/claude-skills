---
name: spring-boot
description: Use when building, reviewing, or extending Spring Boot 4 / Spring Framework applications with WebMVC — including REST controllers, service layers, JPA repositories, configuration classes, async processing with Virtual Threads, and testing. Trigger when the user adds endpoints, wires beans, writes @Configuration classes, sets up async tasks, writes Spring slice tests, or works on any Spring Boot backend feature. Do NOT trigger for reactive/WebFlux applications or non-Spring Java code.
---

# Spring Boot 4 — WebMVC Development

## Stack

| Concern       | Choice                                                                 |
|---------------|------------------------------------------------------------------------|
| Framework     | Spring Boot 4 + Spring MVC                                             |
| Java          | Java 25+                                                               |
| HTTP          | Spring WebMVC (Tomcat) — **not** WebFlux / reactive                   |
| Async         | Virtual Threads (Java 25)                                              |
| Data          | Spring JDBC (`JdbcClient`)                                             |
| Testing       | JUnit 6, AssertJ, BDDMockito, RestTestClient, Testcontainers 2         |

---

## Architecture — Hexagonal

```
Driving adapters          Application          Domain           Driven adapters
(controllers, CLI)  →   Service (orchestrator)  ←→  Objects  →  (repos, events, HTTP)
```

| Layer | Responsibility |
|---|---|
| **Domain** | Business logic, invariants, state transitions — lives in plain Java objects |
| **Application Service** | Orchestrates: load → invoke domain → persist → publish events |
| **Driving adapter** | `@RestController` — translates HTTP into application service calls |
| **Driven adapter** | `JdbcOrderRepository`, HTTP clients — implement domain-defined ports |

**Domain objects are not anemic.** They own their rules. Services do not make decisions — they delegate to the domain and coordinate infrastructure.

---

## Bean Instantiation — Prefer `@Bean` in `@Configuration`

Prefer explicit `@Bean` factory methods inside `@Configuration` classes over class-level stereotype annotations (`@Component`, `@Service`, `@Repository`).

**Why this matters:** explicit `@Bean` declarations make the full wiring visible in one place, are trivial to swap in tests by providing an alternative `@Bean`, and eliminate ambiguity from classpath scanning.

### Do this

```java
@Configuration
public class OrderConfiguration {

    @Bean
    public OrderService orderService(OrderRepository repository,
                                     ApplicationEventPublisher events) {
        return new OrderService(repository, events);
    }

    @Bean
    public NotificationSender notificationSender(MailProperties props) {
        return new SmtpNotificationSender(props);
    }
}
```

### Not this

```java
@Service          // avoid — register via @Bean in a @Configuration class instead
public class OrderService { ... }

@Component        // avoid — prefer explicit @Bean
public class SmtpNotificationSender { ... }
```

**Exceptions — these keep their own annotations:**
- `@RestController` on controllers (conventional, fine)
- `@ControllerAdvice` on exception handlers (MVC contract; the class still needs it, but register the bean via `@Bean`)

---

## Web Layer — `@RestController`

```java
@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @GetMapping("/{id}")
    public ResponseEntity<OrderResponse> getOrder(@PathVariable String id) {
        return orderService.findById(id)
                .map(OrderResponse::from)
                .map(ResponseEntity::ok)
                .orElseThrow(() -> new OrderNotFoundException(id));
    }

    @PostMapping
    public ResponseEntity<OrderResponse> createOrder(
            @RequestBody CreateOrderRequest request) {
        var order = orderService.create(request);
        var location = URI.create("/api/orders/" + order.getId());
        return ResponseEntity.created(location).body(OrderResponse.from(order));
    }
}
```

- Always inject via constructor — never field injection (`@Autowired` on fields).
- Validate input with explicit Java checks in the service layer — never `@Valid` / Bean Validation annotations.
- Return `ResponseEntity<T>` to make HTTP semantics explicit.

---

## Domain Layer

Business logic belongs in the domain object, not in the service. The domain object validates its own invariants, enforces state transitions, and expresses the ubiquitous language of the problem.

### Import rules for domain classes

Domain classes may only import:
- `java.*` standard library
- `org.jspecify.annotations.*` for nullability
- Other domain classes within the same module

**No Spring imports of any kind** — not `org.springframework.*`, not even `StringUtils`. Use `java.util.Objects` or plain Java instead.

### Nullability — annotate with JSpecify

Use `@NullMarked` at the class (or package) level to declare all types non-null by default. Mark exceptions explicitly with `@Nullable`. This gives static analysis tools a complete nullability contract without per-parameter `@NonNull` noise.

```java
import org.jspecify.annotations.NullMarked;
import org.jspecify.annotations.Nullable;

@NullMarked
public class Order {

    private final String id;
    private Status status;
    private final List<OrderLine> lines;

    private Order(String id, Status status, List<OrderLine> lines) {
        this.id = id;
        this.status = status;
        this.lines = List.copyOf(lines);
    }

    // Factory — validates on creation
    public static Order create(String id, List<OrderLine> lines) {
        Objects.requireNonNull(id, "id must not be null");
        if (lines.isEmpty()) {
            throw new IllegalArgumentException("order must have at least one line");
        }
        return new Order(id, Status.PENDING, lines);
    }

    // Business behaviour — state transition with rule enforcement
    public void ship() {
        if (status != Status.PENDING) {
            throw new IllegalStateException("only PENDING orders can be shipped, was: " + status);
        }
        this.status = Status.SHIPPED;
    }

    public void cancel() {
        if (status == Status.SHIPPED) {
            throw new IllegalStateException("shipped orders cannot be cancelled");
        }
        this.status = Status.CANCELLED;
    }

    // Domain calculation
    public Money totalAmount() {
        return lines.stream()
                .map(OrderLine::subtotal)
                .reduce(Money.ZERO, Money::add);
    }

    public String getId()             { return id; }
    public Status getStatus()         { return status; }
    public List<OrderLine> getLines() { return lines; }
}
```

### Ports (driven interfaces, also in the domain)

Domain-defined ports follow the same import and nullability rules. Never return null — use `Optional` for absent values:

```java
import org.jspecify.annotations.NullMarked;

@NullMarked
public interface OrderRepository {
    Optional<Order> findById(String id);
    List<Order> findByStatus(Status status);
    void save(Order order);
}
```

---

## Application Service (Orchestrator)

The service loads domain objects, delegates decisions to them, then coordinates persistence and events. It contains no business rules itself.

```java
public class OrderService {

    private final OrderRepository repository;
    private final ApplicationEventPublisher events;

    public OrderService(OrderRepository repository, ApplicationEventPublisher events) {
        this.repository = repository;
        this.events = events;
    }

    @Transactional
    public Order create(CreateOrderRequest request) {
        var order = Order.create(UUID.randomUUID().toString(), request.lines()); // domain decides
        repository.save(order);
        events.publishEvent(new OrderCreatedEvent(order));
        return order;
    }

    @Transactional
    public void ship(String id) {
        var order = repository.findById(id)
                .orElseThrow(() -> new OrderNotFoundException(id));
        order.ship();                                   // domain decides
        repository.save(order);
        events.publishEvent(new OrderShippedEvent(order));
    }

    @Transactional(readOnly = true)
    public Optional<Order> findById(String id) {
        return repository.findById(id);
    }
}
```

- Place `@Transactional` at the application service layer, not on the repository.
- Use `@Transactional(readOnly = true)` on every method that only reads data — never on write methods.
- No `@Service` annotation — registered via `@Bean` in a `@Configuration` class.

---

## Error Handling

Register the exception handler as a `@Bean` inside a `@Configuration` class. The class still needs `@ControllerAdvice` so Spring MVC recognises it:

```java
@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(OrderNotFoundException.class)
    public ResponseEntity<ProblemDetail> handleNotFound(OrderNotFoundException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(problem);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ProblemDetail> handleIllegalArgument(IllegalArgumentException ex) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
        return ResponseEntity.badRequest().body(problem);
    }
}

@Configuration
public class WebMvcConfiguration {

    @Bean
    public GlobalExceptionHandler globalExceptionHandler() {
        return new GlobalExceptionHandler();
    }
}
```

Use `ProblemDetail` (RFC 9457, built into Spring 6+) rather than custom error envelopes.

---

## Async with Virtual Threads

Spring Boot 4 on Java 25 — enable virtual threads globally for the Tomcat executor:

```yaml
# application.yml
spring:
  threads:
    virtual:
      enabled: true
```

This replaces platform threads with virtual threads for all request handling automatically. Blocking I/O (database calls, HTTP clients, file access) becomes cheap with Java 25 virtual threads — no reactive programming, no thread pool sizing.

### Explicit background task submission

For fire-and-forget or parallel tasks outside the request thread:

```java
@Configuration
public class AsyncConfiguration {

    @Bean
    public Executor virtualThreadExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }
}
```

Usage in a service:

```java
public class ReportService {

    private final Executor executor;

    public ReportService(Executor executor) {
        this.executor = executor;
    }

    public void generateAsync(String reportId) {
        CompletableFuture.runAsync(() -> generate(reportId), executor);
    }
}
```

**Do not use `@Async` with `ThreadPoolTaskExecutor`** — virtual threads make this pattern obsolete. Each task gets its own virtual thread; there is no pool to tune.

---

## Data Layer — Spring JDBC

The domain defines `OrderRepository` as a port (see Domain Layer above); the JDBC adapter implements it. The domain has zero knowledge of SQL or Spring.

Prefer `JdbcClient` (Spring 6.1+) for explicit SQL control and no ORM magic.

Register the adapter as `@Bean` in a `@Configuration` class:

```java
@Configuration
public class OrderDataConfiguration {

    @Bean
    public OrderRepository orderRepository(JdbcClient jdbcClient) {
        return new JdbcOrderRepository(jdbcClient);
    }
}
```

Implement with `JdbcClient`:

```java
public class JdbcOrderRepository implements OrderRepository {

    private final JdbcClient jdbcClient;

    public JdbcOrderRepository(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    @Override
    public Optional<Order> findById(String id) {
        return jdbcClient.sql("SELECT * FROM orders WHERE id = :id")
                .param("id", id)
                .query(Order.class)
                .optional();
    }

    @Override
    public List<Order> findByStatus(Status status) {
        return jdbcClient.sql("SELECT * FROM orders WHERE status = :status")
                .param("status", status.name())
                .query(Order.class)
                .list();
    }

    @Override
    public Order save(Order order) {
        jdbcClient.sql("""
                INSERT INTO orders (id, status, created_at)
                VALUES (:id, :status, :createdAt)
                ON CONFLICT (id) DO UPDATE
                  SET status = :status
                """)
                .param("id", order.getId())
                .param("status", order.getStatus().name())
                .param("createdAt", order.getCreatedAt())
                .update();
        return order;
    }
}
```

Model classes are plain Java — no `@Entity`, no ORM annotations:

```java
public record Order(String id, Status status, Instant createdAt) {}
```

---

## Configuration Properties

Bind external config to a typed record via `@ConfigurationProperties` and expose it as a `@Bean`:

```java
@ConfigurationProperties(prefix = "app.payment")
public record PaymentProperties(String baseUrl, Duration timeout) {}

@Configuration
@EnableConfigurationProperties(PaymentProperties.class)
public class PaymentConfiguration {

    @Bean
    public PaymentClient paymentClient(PaymentProperties props) {
        return new HttpPaymentClient(props.baseUrl(), props.timeout());
    }
}
```

---

# Testing

## Stack

| Concern       | Library                                                                        |
|---------------|--------------------------------------------------------------------------------|
| Runner        | JUnit 6 (`@Test`, `@ExtendWith`, `@ParameterizedTest`)                         |
| Assertions    | AssertJ (`assertThat(...)`)                                                    |
| Mocking       | Mockito via BDD notation (`BDDMockito`)                                        |
| HTTP stubbing | WireMock                                                                       |
| HTTP API tests | REST Assured + `@SpringBootTest(RANDOM_PORT)` + Testcontainers                |
| Slice tests   | Spring Boot 4 Test (`@JdbcTest`, `@SpringBootTest`)                            |
| Containers    | Testcontainers 2.0                                                             |

---

## Structure: Arrange / Act / Assert

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

## Test Naming

```
should_<expected_behavior>_when_<condition>

should_return_order_when_id_exists
should_throw_not_found_when_id_missing
should_publish_event_when_order_created
```

Test class name mirrors the class under test: `OrderService` → `OrderServiceTest`.

---

## Unit Tests

### Domain Object Tests (no mocks needed)

Domain logic is pure Java — test it directly without any Spring or Mockito overhead:

```java
class OrderTest {

    @Test
    void should_start_in_pending_status() {
        var order = Order.create("id-1", List.of(new OrderLine("item-1", 2, Money.of(10))));

        assertThat(order.getStatus()).isEqualTo(Status.PENDING);
    }

    @Test
    void should_transition_to_shipped_when_pending() {
        var order = Order.create("id-1", List.of(new OrderLine("item-1", 1, Money.of(5))));

        order.ship();

        assertThat(order.getStatus()).isEqualTo(Status.SHIPPED);
    }

    @Test
    void should_reject_ship_when_already_shipped() {
        var order = Order.create("id-1", List.of(new OrderLine("item-1", 1, Money.of(5))));
        order.ship();

        assertThatThrownBy(order::ship)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("SHIPPED");
    }

    @Test
    void should_calculate_total_amount() {
        var order = Order.create("id-1", List.of(
                new OrderLine("a", 2, Money.of(10)),
                new OrderLine("b", 1, Money.of(5))
        ));

        assertThat(order.totalAmount()).isEqualTo(Money.of(25));
    }
}
```

### Application Service Tests (mock the ports)

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository repository;

    @Mock
    private ApplicationEventPublisher events;

    @InjectMocks
    private OrderService service;
}
```

### BDD Mockito — always use this, never `Mockito.when` / `Mockito.verify`

```java
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willThrow;
```

**Stubbing:**

```java
given(repository.findById("123")).willReturn(Optional.of(order));
given(repository.save(any(Order.class))).willAnswer(i -> i.getArgument(0));
willThrow(new DataAccessException("db down") {}).given(repository).findById("x");
```

**Verification:**

```java
then(repository).should().save(any(Order.class));
then(repository).should(never()).delete(any());
then(repository).shouldHaveNoMoreInteractions();
```

### AssertJ

```java
// Collections
assertThat(results)
    .hasSize(2)
    .extracting(Order::getId)
    .containsExactly("1", "2");

// Exceptions
assertThatThrownBy(() -> service.findById(null))
    .isInstanceOf(IllegalArgumentException.class)
    .hasMessageContaining("id must not be null");

// Optional
assertThat(result)
    .isPresent()
    .contains(expectedOrder);

// Multiple failures in one test
assertSoftly(softly -> {
    softly.assertThat(order.getId()).isEqualTo("123");
    softly.assertThat(order.getStatus()).isEqualTo(Status.PENDING);
});
```

---

## HTTP API Tests — REST Assured

Treat the running application as a black box: boot the full context on a random port, use a real database via Testcontainers, and drive the API with REST Assured. Nothing is mocked inside the Spring context — this mirrors production as closely as possible.

```java
import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
class OrderApiTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @LocalServerPort
    int port;

    @BeforeEach
    void setUp() {
        RestAssured.port = port;
    }

    @Test
    void should_create_order_and_return_201() {
        given()
            .contentType(ContentType.JSON)
            .body("""
                    {"itemId": "item-1", "quantity": 2}
                    """)
        .when()
            .post("/api/orders")
        .then()
            .statusCode(201)
            .header("Location", containsString("/api/orders/"))
            .body("status", equalTo("PENDING"));
    }

    @Test
    void should_return_200_with_order_when_found() {
        // Arrange — create via the API itself to stay black-box
        var location = given()
            .contentType(ContentType.JSON)
            .body("""{"itemId": "item-1", "quantity": 1}""")
        .when()
            .post("/api/orders")
        .then()
            .statusCode(201)
            .extract().header("Location");

        // Act & Assert
        given()
        .when()
            .get(location)
        .then()
            .statusCode(200)
            .body("status", equalTo("PENDING"));
    }

    @Test
    void should_return_404_when_order_not_found() {
        given()
        .when()
            .get("/api/orders/non-existent-id")
        .then()
            .statusCode(404)
            .body("status", equalTo(404));
    }
}
```

**Why this approach:**
- The full HTTP → controller → service → domain → database path executes — no hidden mock surprises
- Tests verify serialisation, routing, error handling, and HTTP semantics together
- Failures mean something is genuinely broken, not that a mock was misconfigured

---

## Repository Layer — `@JdbcTest`

`@JdbcTest` starts an in-memory database and configures `JdbcClient` — no full Spring context needed:

```java
@JdbcTest
@Import(JdbcOrderRepository.class)
class JdbcOrderRepositoryTest {

    @Autowired
    private JdbcOrderRepository repository;

    @Test
    void should_find_by_status() {
        // Arrange
        repository.save(new Order("1", Status.PENDING, Instant.now()));
        repository.save(new Order("2", Status.SHIPPED, Instant.now()));

        // Act
        var results = repository.findByStatus(Status.PENDING);

        // Assert
        assertThat(results)
                .hasSize(1)
                .extracting(Order::id)
                .containsExactly("1");
    }
}
```

---

## Testcontainers

Declare containers `static` to share them across the full test class and avoid restart overhead between tests. The HTTP API test examples above show the full pattern — `@ServiceConnection` wires the container's coordinates into Spring Boot's auto-configuration automatically, no manual `@DynamicPropertySource` needed.

---

## HTTP Stubbing — WireMock

Use when the application makes outbound HTTP calls to external services. WireMock stubs the external service; REST Assured drives your application from the outside — the full chain runs.

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
@AutoConfigureWireMock(port = 0)   // WireMock on a random port, URL injected via @Value
class PaymentFlowApiTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @LocalServerPort
    int port;

    @BeforeEach
    void setUp() {
        RestAssured.port = port;
    }

    @Test
    void should_return_200_when_payment_confirmed() {
        // Arrange — stub the external payment service
        stubFor(post(urlEqualTo("/payments"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"status\":\"CONFIRMED\"}")));

        // Act & Assert — drive the application via HTTP, not internal classes
        given()
            .contentType(ContentType.JSON)
            .body("""{"orderId": "order-1", "amount": 100}""")
        .when()
            .post("/api/payments/charge")
        .then()
            .statusCode(200)
            .body("status", equalTo("CONFIRMED"));
    }
}
```

---

## What NOT to Do

**Architecture:**
- Do not put business logic in services — services are orchestrators; rules, invariants, and state transitions belong in domain objects
- Do not create anemic domain objects (plain data bags with only getters/setters) — they must own their behaviour
- Do not let domain objects import `org.springframework.*` — domain classes are plain Java; use `java.util.Objects` not Spring `StringUtils`
- Do not return `null` from domain methods — use `Optional<T>` for absent values
- Do not omit JSpecify annotations on domain classes — annotate every domain class/interface with `@NullMarked` and mark exceptions with `@Nullable`

**Beans and wiring:**
- Do not annotate service/component classes with `@Service` or `@Component` — register them via `@Bean` in a `@Configuration` class
- Do not use field injection (`@Autowired` on fields) — always use constructor injection
- Do not use `@Valid` or Bean Validation annotations — validate in the domain object's factory/constructor with `Objects.requireNonNull`, guard clauses, and `IllegalArgumentException`
- Do not use plain `@Transactional` on read-only service methods — use `@Transactional(readOnly = true)` so the database and connection pool can optimise accordingly
- Do not use `@Async` with `ThreadPoolTaskExecutor` — use virtual threads

**Testing:**
- Do not use `@WebMvcTest` with mocked beans for HTTP layer testing — use REST Assured + `@SpringBootTest(RANDOM_PORT)` + Testcontainers for real black-box coverage
- Do not use `RestTestClient` or `MockMvc` for HTTP API tests — REST Assured makes real HTTP calls against a running server
- Do not use `Mockito.when(...)` — always use `BDDMockito.given(...)`
- Do not use `Mockito.verify(...)` — always use `then(...).should(...)`
- Do not use `assertTrue(x != null)` — use AssertJ (`assertThat(x).isNotNull()`)
- Do not share mutable state between test methods
- Do not use camelCase for test method names — always use `snake_case`
