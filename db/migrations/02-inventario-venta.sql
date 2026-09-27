-- ═══════════════════════════════════════════════════════════════════════
--  INVENTARIO
--
--  Las fichas se generan y se cargan en el router ANTES de venderse.
--  Consecuencia: es imposible cobrarle a alguien sin poder entregarle
--  nada. El pago no crea una ficha, revela una que ya estaba lista.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE importacion (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id           uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    punto_id              uuid NOT NULL,
    usuario_id            uuid NOT NULL,

    archivo               text NOT NULL,

    -- Resumen del CONTENIDO, no de los bytes: se calcula sobre las filas
    -- ordenadas. Así el mismo archivo renombrado o reordenado se
    -- reconoce como ya importado.
    huella                text NOT NULL,

    filas_leidas          integer NOT NULL CHECK (filas_leidas >= 0),
    -- Una importación que no agregó nada no debe existir.
    filas_nuevas          integer NOT NULL CHECK (filas_nuevas > 0),

    -- Lo que respondió el supervisor a "¿ya están en el router?".
    -- Si luego aparecen códigos muertos, se sabe quién lo afirmó.
    en_router_al_importar boolean NOT NULL,

    importado_en          timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (punto_id, comercio_id)   REFERENCES punto (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id),

    -- El mismo contenido no se importa dos veces en el mismo comercio.
    UNIQUE (comercio_id, huella),
    UNIQUE (id, comercio_id),
    CHECK (filas_nuevas <= filas_leidas)
);


CREATE TABLE lote (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id      uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    punto_id         uuid NOT NULL,
    plan_id          uuid NOT NULL,
    importacion_id   uuid,                  -- NULL si lo generó la app

    cantidad         integer NOT NULL CHECK (cantidad > 0),
    impreso_en       timestamptz,
    anulado_en       timestamptz,
    motivo_anulacion text,
    creado_en        timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (punto_id, comercio_id)       REFERENCES punto (id, comercio_id),
    FOREIGN KEY (plan_id, comercio_id)        REFERENCES plan (id, comercio_id),
    FOREIGN KEY (importacion_id, comercio_id) REFERENCES importacion (id, comercio_id),

    UNIQUE (id, comercio_id),
    -- Permite que `ficha` herede plan y punto sin poder contradecirlos.
    UNIQUE (id, plan_id, punto_id),
    CHECK ((anulado_en IS NULL) = (motivo_anulacion IS NULL))
);

CREATE INDEX ON lote (comercio_id, plan_id);


-- El centro del modelo: todo el negocio es el ciclo de vida de una ficha.
CREATE TABLE ficha (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id      uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    punto_id         uuid NOT NULL,
    lote_id          uuid NOT NULL,
    plan_id          uuid NOT NULL,

    -- Lo que el cliente teclea. La parte aleatoria excluye O, I, 0 y 1:
    -- se confunden en un celular con mala luz.
    codigo           text NOT NULL
                     CHECK (codigo ~ '^[A-Z0-9]{2,8}-[A-HJ-NP-Z2-9]{4,12}$'),

    origen           text NOT NULL DEFAULT 'importada'
                     CHECK (origen IN ('app','importada')),

    estado           text NOT NULL DEFAULT 'disponible'
                     CHECK (estado IN ('disponible','reservada','vendida',
                                       'activada','agotada','expirada','anulada')),

    -- Una ficha que no está en el router es un código MUERTO. Un trigger
    -- impide reservarla y el stock vendible no la cuenta.
    en_router        boolean NOT NULL DEFAULT false,
    router_conf_en   timestamptz,

    reservada_hasta  timestamptz,
    vendida_en       timestamptz,
    primer_login_en  timestamptz,
    expira_en        timestamptz,
    creado_en        timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (lote_id, plan_id, punto_id) REFERENCES lote (id, plan_id, punto_id),
    FOREIGN KEY (lote_id, comercio_id)       REFERENCES lote (id, comercio_id),

    -- ⚠ CORRECCIÓN v7: en v6 el código era la clave principal, global.
    -- Dos comercios pueden generar el mismo código legítimamente.
    UNIQUE (comercio_id, codigo),
    UNIQUE (id, comercio_id),

    CHECK (en_router = (router_conf_en IS NOT NULL)),
    CHECK (estado <> 'reservada' OR reservada_hasta IS NOT NULL),
    CHECK (estado NOT IN ('vendida','activada','agotada','expirada')
           OR vendida_en IS NOT NULL),
    CHECK (estado NOT IN ('activada','agotada') OR primer_login_en IS NOT NULL)
);

-- Índice PARCIAL: contiene SOLO las fichas vendibles. Por eso contar el
-- stock cuesta lo mismo con 1.200 fichas que con 150.000 vendidas
-- acumuladas: el costo crece con el inventario, no con el historial.
CREATE INDEX ficha_pool ON ficha (comercio_id, plan_id)
    WHERE estado = 'disponible' AND en_router;

CREATE INDEX ficha_sin_cargar ON ficha (comercio_id, plan_id)
    WHERE estado = 'disponible' AND NOT en_router;

CREATE INDEX ON ficha (lote_id);
CREATE INDEX ON ficha (comercio_id, estado);


-- ═══════════════════════════════════════════════════════════════════════
--  TRANSACCIÓN
-- ═══════════════════════════════════════════════════════════════════════

-- ⚠ CORRECCIÓN v7: el número de orden se calculaba con MAX(numero)+1.
-- En SQLite había un solo escritor y era seguro. En PostgreSQL, dos
-- ventas simultáneas leen el mismo máximo y ambas intentan el mismo
-- número: una falla y el operario ve un error sin motivo aparente.
-- Una secuencia por comercio entrega números únicos sin bloquear.
CREATE TABLE contador_orden (
    comercio_id uuid PRIMARY KEY REFERENCES comercio(id) ON DELETE RESTRICT,
    siguiente   bigint NOT NULL DEFAULT 1 CHECK (siguiente > 0)
);

CREATE FUNCTION siguiente_numero_orden(p_comercio uuid) RETURNS bigint
LANGUAGE sql AS $$
    INSERT INTO contador_orden (comercio_id, siguiente)
    VALUES (p_comercio, 2)
    ON CONFLICT (comercio_id)
    DO UPDATE SET siguiente = contador_orden.siguiente + 1
    RETURNING siguiente - 1;
$$;


-- La venta que el operario tiene abierta: mutable y con vencimiento.
CREATE TABLE orden (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id     uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    turno_id        uuid NOT NULL,
    usuario_id      uuid NOT NULL,
    ficha_id        uuid NOT NULL,
    plan_id         uuid NOT NULL,
    cliente_id      uuid,                   -- opcional

    -- Número corto y legible: "orden 1523". Un UUID no se dice en voz alta.
    numero          bigint NOT NULL,

    -- COPIA del precio al abrir la orden. Los catálogos cambian; lo que
    -- ya se le dijo al cliente, no.
    monto_centimos  centimos_pos NOT NULL,

    estado          text NOT NULL DEFAULT 'abierta'
                    CHECK (estado IN ('abierta','pagada','cancelada','expirada')),

    expira_en       timestamptz NOT NULL,
    creado_en       timestamptz NOT NULL DEFAULT ahora(),
    resuelta_en     timestamptz,

    FOREIGN KEY (turno_id, comercio_id)   REFERENCES turno (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id),
    FOREIGN KEY (ficha_id, comercio_id)   REFERENCES ficha (id, comercio_id),
    FOREIGN KEY (plan_id, comercio_id)    REFERENCES plan (id, comercio_id),
    FOREIGN KEY (cliente_id, comercio_id) REFERENCES cliente (id, comercio_id),

    -- ⚠ CORRECCIÓN v7: el número era único GLOBAL. Cada comercio tiene
    -- su propia numeración empezando en 1.
    UNIQUE (comercio_id, numero),
    UNIQUE (id, comercio_id),
    CHECK ((estado = 'abierta') = (resuelta_en IS NULL))
);

-- Una ficha no puede tener dos órdenes abiertas a la vez.
CREATE UNIQUE INDEX orden_una_abierta ON orden (ficha_id) WHERE estado = 'abierta';
CREATE INDEX ON orden (turno_id);


-- Cada intento de cobro. Una orden puede tener varios; solo uno exitoso.
CREATE TABLE pago (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id     uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    orden_id        uuid NOT NULL,

    metodo          text NOT NULL CHECK (metodo IN ('efectivo','manual')),

    -- Por qué se registró a mano. 'pos_externo' es el método NORMAL:
    -- el cobro se valida en el POS del negocio y se copia la referencia.
    motivo_manual   text CHECK (motivo_manual IN
                    ('pos_externo','sin_internet','cuenta_personal',
                     'monto_distinto','otro')),

    medio           text CHECK (medio IN ('QR','YAPE','PLIN','CARD','TRANSFERENCIA')),

    -- Número del voucher del POS.
    referencia      text,

    estado          text NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','exitoso','fallido','expirado','devuelto')),

    monto_centimos  centimos_pos NOT NULL,

    -- Cuánto entregó el cliente en efectivo. El VUELTO no se guarda: se
    -- calcula restando el precio. Un dato derivado no se almacena.
    recibido_centimos centimos_pos,

    confirmado_por  uuid,
    detalle         text,

    -- Conciliación: un supervisor coteja contra el reporte del POS.
    -- La base puede comprobar que una referencia tiene la forma correcta
    -- y que no se repite; NO puede saber si es real. Por eso existe.
    conciliado_en   timestamptz,
    conciliado_por  uuid,

    devuelto_en     timestamptz,
    creado_en       timestamptz NOT NULL DEFAULT ahora(),
    resuelto_en     timestamptz,

    FOREIGN KEY (orden_id, comercio_id)       REFERENCES orden (id, comercio_id),
    FOREIGN KEY (confirmado_por, comercio_id) REFERENCES usuario (id, comercio_id),
    FOREIGN KEY (conciliado_por, comercio_id) REFERENCES usuario (id, comercio_id),

    UNIQUE (id, comercio_id),

    CHECK (metodo <> 'efectivo' OR (referencia IS NULL AND motivo_manual IS NULL
                                    AND medio IS NULL)),
    -- Un pago en efectivo no puede recibir menos que el precio.
    CHECK (recibido_centimos IS NULL OR
           (metodo = 'efectivo' AND recibido_centimos >= monto_centimos)),

    -- Un pago manual exige motivo, y si es del POS también medio y una
    -- referencia con forma de referencia: atrapa los errores de tipeo
    -- más comunes (espacios, guiones, un dígito de más).
    CHECK (metodo <> 'manual' OR motivo_manual IS NOT NULL),
    CHECK (motivo_manual IS DISTINCT FROM 'pos_externo' OR
           (medio IS NOT NULL AND referencia ~ '^[A-Za-z0-9]{4,20}$')),

    CHECK ((conciliado_en IS NULL) = (conciliado_por IS NULL)),
    CHECK (conciliado_en IS NULL OR (metodo = 'manual'
                                     AND estado IN ('exitoso','devuelto'))),
    CHECK ((estado = 'devuelto') = (devuelto_en IS NOT NULL)),
    CHECK ((estado = 'pendiente') = (resuelto_en IS NULL))
);

-- ⚠ CORRECCIÓN v7: la referencia era única GLOBAL. Dos comercios pueden
-- tener legítimamente el mismo número de voucher de sus POS distintos.
CREATE UNIQUE INDEX pago_referencia ON pago (comercio_id, referencia)
    WHERE referencia IS NOT NULL;

-- Un solo pago exitoso por orden.
CREATE UNIQUE INDEX pago_un_exito ON pago (orden_id) WHERE estado = 'exitoso';
CREATE INDEX ON pago (comercio_id, conciliado_en) WHERE metodo = 'manual';


-- El hecho comercial consumado. INMUTABLE: una venta nunca se modifica
-- ni se borra. Un cierre consultado hoy y dentro de un mes da lo mismo.
CREATE TABLE venta (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id       uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    turno_id          uuid NOT NULL,
    usuario_id        uuid NOT NULL,
    ficha_id          uuid NOT NULL,
    orden_id          uuid NOT NULL,
    plan_id           uuid NOT NULL,
    cliente_id        uuid,

    metodo            text NOT NULL CHECK (metodo IN ('efectivo','manual')),
    monto_centimos    centimos_pos NOT NULL,

    -- Fecha local desnormalizada a propósito: el día de una venta es un
    -- hecho del negocio y no debe cambiar si alguien toca la zona
    -- horaria del punto. Además evita convertir al agrupar.
    fecha_local       date NOT NULL,
    hora_local        smallint NOT NULL CHECK (hora_local BETWEEN 0 AND 23),

    comprobante_id    text,
    ocurrida_en       timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (turno_id, comercio_id)   REFERENCES turno (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id),
    FOREIGN KEY (ficha_id, comercio_id)   REFERENCES ficha (id, comercio_id),
    FOREIGN KEY (orden_id, comercio_id)   REFERENCES orden (id, comercio_id),
    FOREIGN KEY (plan_id, comercio_id)    REFERENCES plan (id, comercio_id),
    FOREIGN KEY (cliente_id, comercio_id) REFERENCES cliente (id, comercio_id),

    -- Una ficha se vende una sola vez; una orden produce una sola venta.
    UNIQUE (ficha_id),
    UNIQUE (orden_id),
    UNIQUE (id, comercio_id)
);

CREATE INDEX ON venta (comercio_id, fecha_local);
CREATE INDEX ON venta (turno_id);


-- Anular NO borra ni modifica la venta: la marca como no vigente.
--
-- En v6 la anulación era una "venta de contrapartida", y era imposible
-- de registrar: la venta tiene la ficha y la orden como únicas, así que
-- la contrapartida las repetía y la base la rechazaba.
CREATE TABLE anulacion (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id  uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    venta_id     uuid NOT NULL UNIQUE,      -- una venta se anula una vez
    -- El turno donde SALE el dinero, que puede no ser el de la venta.
    turno_id     uuid NOT NULL,
    usuario_id   uuid NOT NULL,

    motivo       text NOT NULL CHECK (motivo IN
                 ('error_operario','ficha_no_funciona','reclamo_cliente',
                  'devolucion_pos','otro')),
    detalle      text,
    ocurrida_en  timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (venta_id, comercio_id)   REFERENCES venta (id, comercio_id),
    FOREIGN KEY (turno_id, comercio_id)   REFERENCES turno (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id)
);

CREATE INDEX ON anulacion (turno_id);


CREATE TABLE entrega (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id   uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    venta_id      uuid NOT NULL,
    usuario_id    uuid NOT NULL,
    medio         text NOT NULL CHECK (medio IN ('pantalla','impresa')),
    reimpresion   boolean NOT NULL DEFAULT false,
    motivo        text,
    ocurrido_en   timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (venta_id, comercio_id)   REFERENCES venta (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id),
    CHECK (NOT reimpresion OR motivo IS NOT NULL)
);


-- El cliente afirma haber pagado y el operario NO puede verificarlo.
-- Es incómoda a propósito, para que no se use como atajo.
CREATE TABLE incidencia (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id    uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    turno_id       uuid NOT NULL,
    usuario_id     uuid NOT NULL,
    orden_id       uuid,

    tipo           text NOT NULL CHECK (tipo IN
                   ('pago_no_verificable','monto_incorrecto','ficha_no_funciona',
                    'sin_respaldo_pos','otro')),
    descripcion    text NOT NULL CHECK (length(btrim(descripcion)) > 0),
    referencia     text,
    celular        text,
    monto_centimos centimos,

    estado         text NOT NULL DEFAULT 'abierta'
                   CHECK (estado IN ('abierta','resuelta','descartada')),
    resuelto_por   uuid,
    resolucion     text,
    resuelto_en    timestamptz,
    creado_en      timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (turno_id, comercio_id)     REFERENCES turno (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id)   REFERENCES usuario (id, comercio_id),
    FOREIGN KEY (orden_id, comercio_id)     REFERENCES orden (id, comercio_id),
    FOREIGN KEY (resuelto_por, comercio_id) REFERENCES usuario (id, comercio_id),
    CHECK ((estado = 'abierta') = (resuelto_en IS NULL))
);


-- ═══════════════════════════════════════════════════════════════════════
--  ANÁLISIS
-- ═══════════════════════════════════════════════════════════════════════

-- Las ventas dicen qué se ganó; SOLO esta tabla dice qué se dejó de
-- ganar y por qué. Una tarjeta agotada se muestra en gris pero sigue
-- siendo tocable: al tocarla se registra 'sin_stock' sin ningún toque
-- extra del operario.
CREATE TABLE intento_venta (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comercio_id   uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    turno_id      uuid NOT NULL,
    usuario_id    uuid NOT NULL,
    plan_id       uuid,                     -- NULL si pidió algo inexistente

    resultado     text NOT NULL CHECK (resultado IN
                  ('vendida','sin_stock','desistio','precio','sin_servicio',
                   'sin_cambio','otro')),
    nota          text,
    venta_id      uuid,

    fecha_local   date NOT NULL,
    hora_local    smallint NOT NULL CHECK (hora_local BETWEEN 0 AND 23),
    ocurrido_en   timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (turno_id, comercio_id)   REFERENCES turno (id, comercio_id),
    FOREIGN KEY (usuario_id, comercio_id) REFERENCES usuario (id, comercio_id),
    FOREIGN KEY (plan_id, comercio_id)    REFERENCES plan (id, comercio_id),
    FOREIGN KEY (venta_id, comercio_id)   REFERENCES venta (id, comercio_id),

    CHECK ((resultado = 'vendida') = (venta_id IS NOT NULL))
);

CREATE INDEX ON intento_venta (comercio_id, fecha_local);


-- Foto del stock al cerrar cada turno. El conteo en vivo solo conoce el
-- PRESENTE: no puede decir cuántas veces se agotó un plan el mes pasado.
CREATE TABLE stock_cierre (
    comercio_id   uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    turno_id      uuid NOT NULL,
    plan_id       uuid NOT NULL,
    disponibles   integer NOT NULL CHECK (disponibles >= 0),
    sin_cargar    integer NOT NULL CHECK (sin_cargar >= 0),
    minimo        integer NOT NULL,
    registrado_en timestamptz NOT NULL DEFAULT ahora(),

    PRIMARY KEY (turno_id, plan_id),
    FOREIGN KEY (turno_id, comercio_id) REFERENCES turno (id, comercio_id),
    FOREIGN KEY (plan_id, comercio_id)  REFERENCES plan (id, comercio_id)
);


-- Espejo del consumo que reporta el router. Derivado, no autoritativo.
CREATE TABLE consumo (
    ficha_id       uuid PRIMARY KEY,
    comercio_id    uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    bytes_in       bigint NOT NULL DEFAULT 0 CHECK (bytes_in >= 0),
    bytes_out      bigint NOT NULL DEFAULT 0 CHECK (bytes_out >= 0),
    uptime_seg     bigint NOT NULL DEFAULT 0 CHECK (uptime_seg >= 0),
    sesiones       integer NOT NULL DEFAULT 0 CHECK (sesiones >= 0),
    actualizado_en timestamptz NOT NULL DEFAULT ahora(),

    FOREIGN KEY (ficha_id, comercio_id) REFERENCES ficha (id, comercio_id)
);


-- Registro de auditoría. Antes era la cola de sincronización (`outbox`);
-- centralizado ya no hace falta sincronizar, pero el rastro de quién
-- hizo qué sigue siendo valioso.
CREATE TABLE auditoria (
    id           bigserial PRIMARY KEY,
    comercio_id  uuid NOT NULL REFERENCES comercio(id) ON DELETE RESTRICT,
    usuario_id   uuid,
    entidad      text NOT NULL,
    entidad_id   uuid NOT NULL,
    accion       text NOT NULL CHECK (accion IN ('crear','actualizar','anular')),
    datos        jsonb,
    ocurrido_en  timestamptz NOT NULL DEFAULT ahora()
);

CREATE INDEX ON auditoria (comercio_id, ocurrido_en DESC);
