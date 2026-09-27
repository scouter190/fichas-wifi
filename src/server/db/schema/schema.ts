import { pgTable, check, uuid, text , boolean, timestamp, index, foreignKey, pgPolicy, integer, bigint, uniqueIndex, date, smallint, bigserial, jsonb, pgView } from "drizzle-orm/pg-core"
import { sql } from "drizzle-orm"



export const comercio = pgTable("comercio", {
	id: uuid().defaultRandom().notNull(),
	nombre: text().notNull(),
	slug: text().notNull(),
	ruc: text(),
	planSuscripcion: text("plan_suscripcion").default('basico').notNull(),
	activo: boolean().default(true).notNull(),
	suspendidoEn: timestamp("suspendido_en", { withTimezone: true, mode: 'string' }),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	check("comercio_check", sql`activo OR (suspendido_en IS NOT NULL)`),
	check("comercio_nombre_check", sql`(length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 120)`),
	check("comercio_plan_suscripcion_check", sql`plan_suscripcion = ANY (ARRAY['basico'::text, 'pro'::text, 'enterprise'::text])`),
	check("comercio_ruc_check", sql`(ruc IS NULL) OR (ruc ~ '^[0-9]{11}$'::text)`),
	check("comercio_slug_check", sql`slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$'::text`),
]);

export const punto = pgTable("punto", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	nombre: text().notNull(),
	prefijo: text().notNull(),
	tipo: text().default('fijo').notNull(),
	zonaHoraria: text("zona_horaria").default('America/Lima').notNull(),
	reservaTtlMin: integer("reserva_ttl_min").default(10).notNull(),
	poolMinimo: integer("pool_minimo").default(20).notNull(),
	umbralManual: integer("umbral_manual").default(5).notNull(),
	// TODO: failed to parse database type 'centimos_nonneg'
	umbralDescuadre: integer("umbral_descuadre").notNull(),
	refPatronPos: text("ref_patron_pos"),
	activo: boolean().default(true).notNull(),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("punto_comercio_id_idx").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops")).where(sql`activo`),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "punto_comercio_id_fkey"
		}).onDelete("restrict"),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("punto_nombre_check", sql`(length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 80)`),
	check("punto_pool_minimo_check", sql`pool_minimo >= 0`),
	check("punto_prefijo_check", sql`prefijo ~ '^[A-Z0-9]{2,8}$'::text`),
	check("punto_reserva_ttl_min_check", sql`(reserva_ttl_min >= 2) AND (reserva_ttl_min <= 60)`),
	check("punto_tipo_check", sql`tipo = ANY (ARRAY['fijo'::text, 'movil'::text])`),
	check("punto_umbral_manual_check", sql`umbral_manual >= 0`),
]);

export const contadorOrden = pgTable("contador_orden", {
	comercioId: uuid("comercio_id").notNull(),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	siguiente: bigint({ mode: "number" }).default(1).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "contador_orden_comercio_id_fkey"
		}).onDelete("restrict"),
	check("contador_orden_siguiente_check", sql`siguiente > 0`),
]);

export const importacion = pgTable("importacion", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	puntoId: uuid("punto_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	archivo: text().notNull(),
	huella: text().notNull(),
	filasLeidas: integer("filas_leidas").notNull(),
	filasNuevas: integer("filas_nuevas").notNull(),
	enRouterAlImportar: boolean("en_router_al_importar").notNull(),
	importadoEn: timestamp("importado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "importacion_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.puntoId],
			foreignColumns: [punto.id, punto.comercioId],
			name: "importacion_punto_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "importacion_usuario_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("importacion_check", sql`filas_nuevas <= filas_leidas`),
	check("importacion_filas_leidas_check", sql`filas_leidas >= 0`),
	check("importacion_filas_nuevas_check", sql`filas_nuevas > 0`),
]);

export const pago = pgTable("pago", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	ordenId: uuid("orden_id").notNull(),
	metodo: text().notNull(),
	motivoManual: text("motivo_manual"),
	medio: text(),
	referencia: text(),
	estado: text().default('pendiente').notNull(),
	// TODO: failed to parse database type 'centimos_pos'
	montoCentimos: integer("monto_centimos").notNull(),
	// TODO: failed to parse database type 'centimos_pos'
	recibidoCentimos: integer("recibido_centimos"),
	confirmadoPor: uuid("confirmado_por"),
	detalle: text(),
	conciliadoEn: timestamp("conciliado_en", { withTimezone: true, mode: 'string' }),
	conciliadoPor: uuid("conciliado_por"),
	devueltoEn: timestamp("devuelto_en", { withTimezone: true, mode: 'string' }),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
	resueltoEn: timestamp("resuelto_en", { withTimezone: true, mode: 'string' }),
}, (table) => [
	index("pago_comercio_id_conciliado_en_idx").using("btree", table.comercioId.asc().nullsLast().op("timestamptz_ops"), table.conciliadoEn.asc().nullsLast().op("uuid_ops")).where(sql`(metodo = 'manual'::text)`),
	uniqueIndex("pago_referencia").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops"), table.referencia.asc().nullsLast().op("uuid_ops")).where(sql`(referencia IS NOT NULL)`),
	uniqueIndex("pago_un_exito").using("btree", table.ordenId.asc().nullsLast().op("uuid_ops")).where(sql`(estado = 'exitoso'::text)`),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "pago_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.conciliadoPor],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "pago_conciliado_por_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.confirmadoPor],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "pago_confirmado_por_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.ordenId],
			foreignColumns: [orden.id, orden.comercioId],
			name: "pago_orden_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("pago_check", sql`(metodo <> 'efectivo'::text) OR ((referencia IS NULL) AND (motivo_manual IS NULL) AND (medio IS NULL))`),
	check("pago_check1", sql`(recibido_centimos IS NULL) OR ((metodo = 'efectivo'::text) AND ((recibido_centimos)::integer >= (monto_centimos)::integer))`),
	check("pago_check2", sql`(metodo <> 'manual'::text) OR (motivo_manual IS NOT NULL)`),
	check("pago_check3", sql`(motivo_manual IS DISTINCT FROM 'pos_externo'::text) OR ((medio IS NOT NULL) AND (referencia ~ '^[A-Za-z0-9]{4,20}$'::text))`),
	check("pago_check4", sql`(conciliado_en IS NULL) = (conciliado_por IS NULL)`),
	check("pago_check5", sql`(conciliado_en IS NULL) OR ((metodo = 'manual'::text) AND (estado = ANY (ARRAY['exitoso'::text, 'devuelto'::text])))`),
	check("pago_check6", sql`(estado = 'devuelto'::text) = (devuelto_en IS NOT NULL)`),
	check("pago_check7", sql`(estado = 'pendiente'::text) = (resuelto_en IS NULL)`),
	check("pago_estado_check", sql`estado = ANY (ARRAY['pendiente'::text, 'exitoso'::text, 'fallido'::text, 'expirado'::text, 'devuelto'::text])`),
	check("pago_medio_check", sql`medio = ANY (ARRAY['QR'::text, 'YAPE'::text, 'PLIN'::text, 'CARD'::text, 'TRANSFERENCIA'::text])`),
	check("pago_metodo_check", sql`metodo = ANY (ARRAY['efectivo'::text, 'manual'::text])`),
	check("pago_motivo_manual_check", sql`motivo_manual = ANY (ARRAY['pos_externo'::text, 'sin_internet'::text, 'cuenta_personal'::text, 'monto_distinto'::text, 'otro'::text])`),
]);

export const incidencia = pgTable("incidencia", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	ordenId: uuid("orden_id"),
	tipo: text().notNull(),
	descripcion: text().notNull(),
	referencia: text(),
	celular: text(),
	// TODO: failed to parse database type 'centimos'
	montoCentimos: integer("monto_centimos"),
	estado: text().default('abierta').notNull(),
	resueltoPor: uuid("resuelto_por"),
	resolucion: text(),
	resueltoEn: timestamp("resuelto_en", { withTimezone: true, mode: 'string' }),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "incidencia_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.ordenId],
			foreignColumns: [orden.id, orden.comercioId],
			name: "incidencia_orden_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.resueltoPor],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "incidencia_resuelto_por_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "incidencia_turno_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "incidencia_usuario_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("incidencia_check", sql`(estado = 'abierta'::text) = (resuelto_en IS NULL)`),
	check("incidencia_descripcion_check", sql`length(btrim(descripcion)) > 0`),
	check("incidencia_estado_check", sql`estado = ANY (ARRAY['abierta'::text, 'resuelta'::text, 'descartada'::text])`),
	check("incidencia_tipo_check", sql`tipo = ANY (ARRAY['pago_no_verificable'::text, 'monto_incorrecto'::text, 'ficha_no_funciona'::text, 'sin_respaldo_pos'::text, 'otro'::text])`),
]);

export const plan = pgTable("plan", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	codigo: text().notNull(),
	nombre: text().notNull(),
	categoria: text().default('tiempo').notNull(),
	ordenDisplay: integer("orden_display").default(0).notNull(),
	// TODO: failed to parse database type 'centimos_pos'
	precioCentimos: integer("precio_centimos").notNull(),
	limiteTiempoSeg: integer("limite_tiempo_seg"),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	limiteBytes: bigint("limite_bytes", { mode: "number" }),
	validezDias: integer("validez_dias").notNull(),
	rateLimit: text("rate_limit").notNull(),
	stockMinimo: integer("stock_minimo"),
	activo: boolean().default(true).notNull(),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("plan_comercio_id_orden_display_idx").using("btree", table.comercioId.asc().nullsLast().op("int4_ops"), table.ordenDisplay.asc().nullsLast().op("int4_ops")).where(sql`activo`),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "plan_comercio_id_fkey"
		}).onDelete("restrict"),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("plan_categoria_check", sql`categoria = ANY (ARRAY['tiempo'::text, 'datos'::text, 'mixto'::text])`),
	check("plan_check", sql`(limite_tiempo_seg IS NOT NULL) OR (limite_bytes IS NOT NULL)`),
	check("plan_check1", sql`(categoria <> 'tiempo'::text) OR (limite_tiempo_seg IS NOT NULL)`),
	check("plan_check2", sql`(categoria <> 'datos'::text) OR (limite_bytes IS NOT NULL)`),
	check("plan_check3", sql`(categoria <> 'mixto'::text) OR ((limite_tiempo_seg IS NOT NULL) AND (limite_bytes IS NOT NULL))`),
	check("plan_codigo_check", sql`codigo ~ '^[A-Za-z0-9_]{2,20}$'::text`),
	check("plan_limite_bytes_check", sql`(limite_bytes IS NULL) OR (limite_bytes > 0)`),
	check("plan_limite_tiempo_seg_check", sql`(limite_tiempo_seg IS NULL) OR (limite_tiempo_seg > 0)`),
	check("plan_nombre_check", sql`(length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 60)`),
	check("plan_stock_minimo_check", sql`(stock_minimo IS NULL) OR (stock_minimo >= 0)`),
	check("plan_validez_dias_check", sql`validez_dias > 0`),
]);

export const usuario = pgTable("usuario", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	nombre: text().notNull(),
	email: text().notNull(),
	passwordHash: text("password_hash").notNull(),
	rol: text().default('operario').notNull(),
	intentosFallidos: integer("intentos_fallidos").default(0).notNull(),
	bloqueadoHasta: timestamp("bloqueado_hasta", { withTimezone: true, mode: 'string' }),
	ultimoAcceso: timestamp("ultimo_acceso", { withTimezone: true, mode: 'string' }),
	activo: boolean().default(true).notNull(),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("usuario_comercio_id_idx").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops")).where(sql`activo`),
	uniqueIndex("usuario_email_global").using("btree", table.email.asc().nullsLast().op("text_ops")).where(sql`activo`),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "usuario_comercio_id_fkey"
		}).onDelete("restrict"),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("usuario_email_check", sql`(email = lower(email)) AND (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text)`),
	check("usuario_intentos_fallidos_check", sql`intentos_fallidos >= 0`),
	check("usuario_nombre_check", sql`(length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 80)`),
	check("usuario_rol_check", sql`rol = ANY (ARRAY['operario'::text, 'supervisor'::text, 'admin'::text])`),
]);

export const turno = pgTable("turno", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	puntoId: uuid("punto_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	diaOperativo: date("dia_operativo").notNull(),
	abiertoEn: timestamp("abierto_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
	cerradoEn: timestamp("cerrado_en", { withTimezone: true, mode: 'string' }),
	// TODO: failed to parse database type 'centimos_nonneg'
	fondoInicial: integer("fondo_inicial").notNull(),
	// TODO: failed to parse database type 'centimos_nonneg'
	efectivoDeclarado: integer("efectivo_declarado"),
	// TODO: failed to parse database type 'centimos'
	efectivoEsperado: integer("efectivo_esperado"),
	// TODO: failed to parse database type 'centimos'
	diferencia: integer("diferencia"),
	notaCierre: text("nota_cierre"),
}, (table) => [
	index("turno_comercio_id_dia_operativo_idx").using("btree", table.comercioId.asc().nullsLast().op("date_ops"), table.diaOperativo.asc().nullsLast().op("uuid_ops")),
	uniqueIndex("turno_uno_abierto_por_punto").using("btree", table.puntoId.asc().nullsLast().op("uuid_ops")).where(sql`(cerrado_en IS NULL)`),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "turno_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.puntoId],
			foreignColumns: [punto.id, punto.comercioId],
			name: "turno_punto_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "turno_usuario_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("turno_check", sql`(cerrado_en IS NULL) = (efectivo_declarado IS NULL)`),
	check("turno_check1", sql`(cerrado_en IS NULL) OR (cerrado_en >= abierto_en)`),
]);

export const movimientoCaja = pgTable("movimiento_caja", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	tipo: text().notNull(),
	// TODO: failed to parse database type 'centimos'
	montoCentimos: integer("monto_centimos").notNull(),
	motivo: text().notNull(),
	ocurridoEn: timestamp("ocurrido_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("movimiento_caja_turno_id_idx").using("btree", table.turnoId.asc().nullsLast().op("uuid_ops")),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "movimiento_caja_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "movimiento_caja_turno_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "movimiento_caja_usuario_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("movimiento_caja_monto_centimos_check", sql`(monto_centimos)::integer <> 0`),
	check("movimiento_caja_motivo_check", sql`length(btrim(motivo)) > 0`),
	check("movimiento_caja_tipo_check", sql`tipo = ANY (ARRAY['fondo'::text, 'retiro'::text, 'ingreso'::text, 'ajuste'::text])`),
]);

export const cliente = pgTable("cliente", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	// TODO: failed to parse database type 'celular_pe'
	celular: text("celular").notNull(),
	nombre: text(),
	apellido: text(),
	email: text(),
	documentoTipo: text("documento_tipo"),
	documentoNum: text("documento_num"),
	consentimientoEn: timestamp("consentimiento_en", { withTimezone: true, mode: 'string' }).notNull(),
	activo: boolean().default(true).notNull(),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "cliente_comercio_id_fkey"
		}).onDelete("restrict"),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("cliente_check", sql`(documento_tipo IS NULL) = (documento_num IS NULL)`),
	check("cliente_check1", sql`(documento_tipo IS DISTINCT FROM 'DNI'::text) OR (documento_num ~ '^[0-9]{8}$'::text)`),
	check("cliente_documento_tipo_check", sql`documento_tipo = ANY (ARRAY['DNI'::text, 'CE'::text, 'PASAPORTE'::text, 'RUC'::text])`),
	check("cliente_email_check", sql`(email IS NULL) OR (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text)`),
]);

export const lote = pgTable("lote", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	puntoId: uuid("punto_id").notNull(),
	planId: uuid("plan_id").notNull(),
	importacionId: uuid("importacion_id"),
	cantidad: integer().notNull(),
	impresoEn: timestamp("impreso_en", { withTimezone: true, mode: 'string' }),
	anuladoEn: timestamp("anulado_en", { withTimezone: true, mode: 'string' }),
	motivoAnulacion: text("motivo_anulacion"),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("lote_comercio_id_plan_id_idx").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops"), table.planId.asc().nullsLast().op("uuid_ops")),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "lote_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.importacionId],
			foreignColumns: [importacion.id, importacion.comercioId],
			name: "lote_importacion_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.planId],
			foreignColumns: [plan.id, plan.comercioId],
			name: "lote_plan_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.puntoId],
			foreignColumns: [punto.id, punto.comercioId],
			name: "lote_punto_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("lote_cantidad_check", sql`cantidad > 0`),
	check("lote_check", sql`(anulado_en IS NULL) = (motivo_anulacion IS NULL)`),
]);

export const ficha = pgTable("ficha", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	puntoId: uuid("punto_id").notNull(),
	loteId: uuid("lote_id").notNull(),
	planId: uuid("plan_id").notNull(),
	codigo: text().notNull(),
	origen: text().default('importada').notNull(),
	estado: text().default('disponible').notNull(),
	enRouter: boolean("en_router").default(false).notNull(),
	routerConfEn: timestamp("router_conf_en", { withTimezone: true, mode: 'string' }),
	reservadaHasta: timestamp("reservada_hasta", { withTimezone: true, mode: 'string' }),
	vendidaEn: timestamp("vendida_en", { withTimezone: true, mode: 'string' }),
	primerLoginEn: timestamp("primer_login_en", { withTimezone: true, mode: 'string' }),
	expiraEn: timestamp("expira_en", { withTimezone: true, mode: 'string' }),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("ficha_comercio_id_estado_idx").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops"), table.estado.asc().nullsLast().op("text_ops")),
	index("ficha_lote_id_idx").using("btree", table.loteId.asc().nullsLast().op("uuid_ops")),
	index("ficha_pool").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops"), table.planId.asc().nullsLast().op("uuid_ops")).where(sql`((estado = 'disponible'::text) AND en_router)`),
	index("ficha_sin_cargar").using("btree", table.comercioId.asc().nullsLast().op("uuid_ops"), table.planId.asc().nullsLast().op("uuid_ops")).where(sql`((estado = 'disponible'::text) AND (NOT en_router))`),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "ficha_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.loteId],
			foreignColumns: [lote.id, lote.comercioId],
			name: "ficha_lote_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.puntoId, table.loteId, table.planId],
			foreignColumns: [lote.id, lote.puntoId, lote.planId],
			name: "ficha_lote_id_plan_id_punto_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("ficha_check", sql`en_router = (router_conf_en IS NOT NULL)`),
	check("ficha_check1", sql`(estado <> 'reservada'::text) OR (reservada_hasta IS NOT NULL)`),
	check("ficha_check2", sql`(estado <> ALL (ARRAY['vendida'::text, 'activada'::text, 'agotada'::text, 'expirada'::text])) OR (vendida_en IS NOT NULL)`),
	check("ficha_check3", sql`(estado <> ALL (ARRAY['activada'::text, 'agotada'::text])) OR (primer_login_en IS NOT NULL)`),
	check("ficha_codigo_check", sql`codigo ~ '^[A-Z0-9]{2,8}-[A-HJ-NP-Z2-9]{4,12}$'::text`),
	check("ficha_estado_check", sql`estado = ANY (ARRAY['disponible'::text, 'reservada'::text, 'vendida'::text, 'activada'::text, 'agotada'::text, 'expirada'::text, 'anulada'::text])`),
	check("ficha_origen_check", sql`origen = ANY (ARRAY['app'::text, 'importada'::text])`),
]);

export const orden = pgTable("orden", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	fichaId: uuid("ficha_id").notNull(),
	planId: uuid("plan_id").notNull(),
	clienteId: uuid("cliente_id"),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	numero: bigint({ mode: "number" }),
	// TODO: failed to parse database type 'centimos_pos'
	montoCentimos: integer("monto_centimos").notNull(),
	estado: text().default('abierta').notNull(),
	expiraEn: timestamp("expira_en", { withTimezone: true, mode: 'string' }).notNull(),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
	resueltaEn: timestamp("resuelta_en", { withTimezone: true, mode: 'string' }),
}, (table) => [
	index("orden_turno_id_idx").using("btree", table.turnoId.asc().nullsLast().op("uuid_ops")),
	uniqueIndex("orden_una_abierta").using("btree", table.fichaId.asc().nullsLast().op("uuid_ops")).where(sql`(estado = 'abierta'::text)`),
	foreignKey({
			columns: [table.comercioId, table.clienteId],
			foreignColumns: [cliente.id, cliente.comercioId],
			name: "orden_cliente_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "orden_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.fichaId],
			foreignColumns: [ficha.id, ficha.comercioId],
			name: "orden_ficha_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.planId],
			foreignColumns: [plan.id, plan.comercioId],
			name: "orden_plan_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "orden_turno_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "orden_usuario_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("orden_check", sql`(estado = 'abierta'::text) = (resuelta_en IS NULL)`),
	check("orden_estado_check", sql`estado = ANY (ARRAY['abierta'::text, 'pagada'::text, 'cancelada'::text, 'expirada'::text])`),
]);

export const venta = pgTable("venta", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	fichaId: uuid("ficha_id").notNull(),
	ordenId: uuid("orden_id").notNull(),
	planId: uuid("plan_id").notNull(),
	clienteId: uuid("cliente_id"),
	metodo: text().notNull(),
	// TODO: failed to parse database type 'centimos_pos'
	montoCentimos: integer("monto_centimos").notNull(),
	fechaLocal: date("fecha_local").notNull(),
	horaLocal: smallint("hora_local").notNull(),
	comprobanteId: text("comprobante_id"),
	ocurridaEn: timestamp("ocurrida_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("venta_comercio_id_fecha_local_idx").using("btree", table.comercioId.asc().nullsLast().op("date_ops"), table.fechaLocal.asc().nullsLast().op("uuid_ops")),
	index("venta_turno_id_idx").using("btree", table.turnoId.asc().nullsLast().op("uuid_ops")),
	foreignKey({
			columns: [table.comercioId, table.clienteId],
			foreignColumns: [cliente.id, cliente.comercioId],
			name: "venta_cliente_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "venta_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.fichaId],
			foreignColumns: [ficha.id, ficha.comercioId],
			name: "venta_ficha_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.ordenId],
			foreignColumns: [orden.id, orden.comercioId],
			name: "venta_orden_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.planId],
			foreignColumns: [plan.id, plan.comercioId],
			name: "venta_plan_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "venta_turno_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "venta_usuario_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("venta_hora_local_check", sql`(hora_local >= 0) AND (hora_local <= 23)`),
	check("venta_metodo_check", sql`metodo = ANY (ARRAY['efectivo'::text, 'manual'::text])`),
]);

export const anulacion = pgTable("anulacion", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	ventaId: uuid("venta_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	motivo: text().notNull(),
	detalle: text(),
	ocurridaEn: timestamp("ocurrida_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("anulacion_turno_id_idx").using("btree", table.turnoId.asc().nullsLast().op("uuid_ops")),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "anulacion_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "anulacion_turno_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "anulacion_usuario_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.ventaId],
			foreignColumns: [venta.id, venta.comercioId],
			name: "anulacion_venta_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("anulacion_motivo_check", sql`motivo = ANY (ARRAY['error_operario'::text, 'ficha_no_funciona'::text, 'reclamo_cliente'::text, 'devolucion_pos'::text, 'otro'::text])`),
]);

export const entrega = pgTable("entrega", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	ventaId: uuid("venta_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	medio: text().notNull(),
	reimpresion: boolean().default(false).notNull(),
	motivo: text(),
	ocurridoEn: timestamp("ocurrido_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "entrega_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "entrega_usuario_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.ventaId],
			foreignColumns: [venta.id, venta.comercioId],
			name: "entrega_venta_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("entrega_check", sql`(NOT reimpresion) OR (motivo IS NOT NULL)`),
	check("entrega_medio_check", sql`medio = ANY (ARRAY['pantalla'::text, 'impresa'::text])`),
]);

export const intentoVenta = pgTable("intento_venta", {
	id: uuid().defaultRandom().notNull(),
	comercioId: uuid("comercio_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	usuarioId: uuid("usuario_id").notNull(),
	planId: uuid("plan_id"),
	resultado: text().notNull(),
	nota: text(),
	ventaId: uuid("venta_id"),
	fechaLocal: date("fecha_local").notNull(),
	horaLocal: smallint("hora_local").notNull(),
	ocurridoEn: timestamp("ocurrido_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("intento_venta_comercio_id_fecha_local_idx").using("btree", table.comercioId.asc().nullsLast().op("date_ops"), table.fechaLocal.asc().nullsLast().op("date_ops")),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "intento_venta_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.planId],
			foreignColumns: [plan.id, plan.comercioId],
			name: "intento_venta_plan_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "intento_venta_turno_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.usuarioId],
			foreignColumns: [usuario.id, usuario.comercioId],
			name: "intento_venta_usuario_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.ventaId],
			foreignColumns: [venta.id, venta.comercioId],
			name: "intento_venta_venta_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("intento_venta_check", sql`(resultado = 'vendida'::text) = (venta_id IS NOT NULL)`),
	check("intento_venta_hora_local_check", sql`(hora_local >= 0) AND (hora_local <= 23)`),
	check("intento_venta_resultado_check", sql`resultado = ANY (ARRAY['vendida'::text, 'sin_stock'::text, 'desistio'::text, 'precio'::text, 'sin_servicio'::text, 'sin_cambio'::text, 'otro'::text])`),
]);

export const stockCierre = pgTable("stock_cierre", {
	comercioId: uuid("comercio_id").notNull(),
	turnoId: uuid("turno_id").notNull(),
	planId: uuid("plan_id").notNull(),
	disponibles: integer().notNull(),
	sinCargar: integer("sin_cargar").notNull(),
	minimo: integer().notNull(),
	registradoEn: timestamp("registrado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "stock_cierre_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.comercioId, table.planId],
			foreignColumns: [plan.id, plan.comercioId],
			name: "stock_cierre_plan_id_comercio_id_fkey"
		}),
	foreignKey({
			columns: [table.comercioId, table.turnoId],
			foreignColumns: [turno.id, turno.comercioId],
			name: "stock_cierre_turno_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("stock_cierre_disponibles_check", sql`disponibles >= 0`),
	check("stock_cierre_sin_cargar_check", sql`sin_cargar >= 0`),
]);

export const consumo = pgTable("consumo", {
	fichaId: uuid("ficha_id").notNull(),
	comercioId: uuid("comercio_id").notNull(),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	bytesIn: bigint("bytes_in", { mode: "number" }).default(0).notNull(),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	bytesOut: bigint("bytes_out", { mode: "number" }).default(0).notNull(),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	uptimeSeg: bigint("uptime_seg", { mode: "number" }).default(0).notNull(),
	sesiones: integer().default(0).notNull(),
	actualizadoEn: timestamp("actualizado_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "consumo_comercio_id_fkey"
		}).onDelete("restrict"),
	foreignKey({
			columns: [table.fichaId, table.comercioId],
			foreignColumns: [ficha.id, ficha.comercioId],
			name: "consumo_ficha_id_comercio_id_fkey"
		}),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("consumo_bytes_in_check", sql`bytes_in >= 0`),
	check("consumo_bytes_out_check", sql`bytes_out >= 0`),
	check("consumo_sesiones_check", sql`sesiones >= 0`),
	check("consumo_uptime_seg_check", sql`uptime_seg >= 0`),
]);

export const auditoria = pgTable("auditoria", {
	id: bigserial({ mode: "bigint" }).notNull(),
	comercioId: uuid("comercio_id").notNull(),
	usuarioId: uuid("usuario_id"),
	entidad: text().notNull(),
	entidadId: uuid("entidad_id").notNull(),
	accion: text().notNull(),
	datos: jsonb(),
	ocurridoEn: timestamp("ocurrido_en", { withTimezone: true, mode: 'string' }).default(sql`ahora()`).notNull(),
}, (table) => [
	index("auditoria_comercio_id_ocurrido_en_idx").using("btree", table.comercioId.asc().nullsLast().op("timestamptz_ops"), table.ocurridoEn.desc().nullsFirst().op("timestamptz_ops")),
	foreignKey({
			columns: [table.comercioId],
			foreignColumns: [comercio.id],
			name: "auditoria_comercio_id_fkey"
		}).onDelete("restrict"),
	pgPolicy("aislamiento", { as: "permissive", for: "all", to: ["public"], using: sql`(comercio_id = app_comercio())`, withCheck: sql`(comercio_id = app_comercio())`  }),
	check("auditoria_accion_check", sql`accion = ANY (ARRAY['crear'::text, 'actualizar'::text, 'anular'::text])`),
]);
export const vVentaVigente = pgView("v_venta_vigente", {	id: uuid(),
	comercioId: uuid("comercio_id"),
	turnoId: uuid("turno_id"),
	usuarioId: uuid("usuario_id"),
	fichaId: uuid("ficha_id"),
	ordenId: uuid("orden_id"),
	planId: uuid("plan_id"),
	clienteId: uuid("cliente_id"),
	metodo: text(),
	// TODO: failed to parse database type 'centimos_pos'
	montoCentimos: integer("monto_centimos"),
	fechaLocal: date("fecha_local"),
	horaLocal: smallint("hora_local"),
	comprobanteId: text("comprobante_id"),
	ocurridaEn: timestamp("ocurrida_en", { withTimezone: true, mode: 'string' }),
}).as(sql`SELECT id, comercio_id, turno_id, usuario_id, ficha_id, orden_id, plan_id, cliente_id, metodo, monto_centimos, fecha_local, hora_local, comprobante_id, ocurrida_en FROM venta v WHERE NOT (EXISTS ( SELECT 1 FROM anulacion a WHERE a.venta_id = v.id))`);

export const vPool = pgView("v_pool", {	comercioId: uuid("comercio_id"),
	planId: uuid("plan_id"),
	codigo: text(),
	nombre: text(),
	categoria: text(),
	// TODO: failed to parse database type 'centimos_pos'
	precioCentimos: integer("precio_centimos"),
	disponibles: integer(),
	sinCargar: integer("sin_cargar"),
	minimo: integer(),
}).as(sql`WITH disp AS ( SELECT ficha.comercio_id, ficha.plan_id, count(*) AS n FROM ficha WHERE ficha.estado = 'disponible'::text AND ficha.en_router GROUP BY ficha.comercio_id, ficha.plan_id ), pend AS ( SELECT ficha.comercio_id, ficha.plan_id, count(*) AS n FROM ficha WHERE ficha.estado = 'disponible'::text AND NOT ficha.en_router GROUP BY ficha.comercio_id, ficha.plan_id ) SELECT p.comercio_id, p.id AS plan_id, p.codigo, p.nombre, p.categoria, p.precio_centimos, COALESCE(d.n, 0::bigint)::integer AS disponibles, COALESCE(pe.n, 0::bigint)::integer AS sin_cargar, COALESCE(p.stock_minimo, ( SELECT min(pt.pool_minimo) AS min FROM punto pt WHERE pt.comercio_id = p.comercio_id AND pt.activo)) AS minimo FROM plan p LEFT JOIN disp d ON d.plan_id = p.id LEFT JOIN pend pe ON pe.plan_id = p.id WHERE p.activo`);

export const vStockLote = pgView("v_stock_lote", {	comercioId: uuid("comercio_id"),
	loteId: uuid("lote_id"),
	planId: uuid("plan_id"),
	plan: text(),
	cantidad: integer(),
	importacionId: uuid("importacion_id"),
	archivo: text(),
	creadoEn: timestamp("creado_en", { withTimezone: true, mode: 'string' }),
	anuladoEn: timestamp("anulado_en", { withTimezone: true, mode: 'string' }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	disponibles: bigint({ mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	sinCargar: bigint("sin_cargar", { mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	reservadas: bigint({ mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	vendidas: bigint({ mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	anuladas: bigint({ mode: "number" }),
}).as(sql`SELECT l.comercio_id, l.id AS lote_id, l.plan_id, p.nombre AS plan, l.cantidad, l.importacion_id, i.archivo, l.creado_en, l.anulado_en, count(*) FILTER (WHERE f.estado = 'disponible'::text AND f.en_router) AS disponibles, count(*) FILTER (WHERE f.estado = 'disponible'::text AND NOT f.en_router) AS sin_cargar, count(*) FILTER (WHERE f.estado = 'reservada'::text) AS reservadas, count(*) FILTER (WHERE f.estado = ANY (ARRAY['vendida'::text, 'activada'::text, 'agotada'::text, 'expirada'::text])) AS vendidas, count(*) FILTER (WHERE f.estado = 'anulada'::text) AS anuladas FROM lote l JOIN plan p ON p.id = l.plan_id LEFT JOIN importacion i ON i.id = l.importacion_id LEFT JOIN ficha f ON f.lote_id = l.id GROUP BY l.comercio_id, l.id, l.plan_id, p.nombre, l.cantidad, l.importacion_id, i.archivo, l.creado_en, l.anulado_en`);

export const vTurnoActual = pgView("v_turno_actual", {	comercioId: uuid("comercio_id"),
	turnoId: uuid("turno_id"),
	puntoId: uuid("punto_id"),
	diaOperativo: date("dia_operativo"),
	usuario: text(),
	abiertoEn: timestamp("abierto_en", { withTimezone: true, mode: 'string' }),
	// TODO: failed to parse database type 'centimos_nonneg'
	fondoInicial: integer("fondo_inicial"),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	efectivoCobrado: bigint("efectivo_cobrado", { mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	efectivoDevuelto: bigint("efectivo_devuelto", { mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	movimientos: bigint({ mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	efectivoEsperado: bigint("efectivo_esperado", { mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	fichas: bigint({ mode: "number" }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	pagosPos: bigint("pagos_pos", { mode: "number" }),
}).as(sql`SELECT t.comercio_id, t.id AS turno_id, t.punto_id, t.dia_operativo, u.nombre AS usuario, t.abierto_en, t.fondo_inicial, COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM venta v WHERE v.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) AS efectivo_cobrado, COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM anulacion a JOIN venta v ON v.id = a.venta_id WHERE a.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) AS efectivo_devuelto, COALESCE(( SELECT sum(m.monto_centimos::integer) AS sum FROM movimiento_caja m WHERE m.turno_id = t.id AND m.tipo <> 'fondo'::text), 0::bigint) AS movimientos, t.fondo_inicial::integer + COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM venta v WHERE v.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) - COALESCE(( SELECT sum(v.monto_centimos::integer) AS sum FROM anulacion a JOIN venta v ON v.id = a.venta_id WHERE a.turno_id = t.id AND v.metodo = 'efectivo'::text), 0::bigint) + COALESCE(( SELECT sum(m.monto_centimos::integer) AS sum FROM movimiento_caja m WHERE m.turno_id = t.id AND m.tipo <> 'fondo'::text), 0::bigint) AS efectivo_esperado, ( SELECT count(*) AS count FROM v_venta_vigente v WHERE v.turno_id = t.id) AS fichas, ( SELECT count(*) AS count FROM pago pg JOIN orden o ON o.id = pg.orden_id WHERE o.turno_id = t.id AND pg.motivo_manual = 'pos_externo'::text AND pg.estado = 'exitoso'::text) AS pagos_pos FROM turno t JOIN usuario u ON u.id = t.usuario_id WHERE t.cerrado_en IS NULL`);

export const vPendienteConciliar = pgView("v_pendiente_conciliar", {	comercioId: uuid("comercio_id"),
	pagoId: uuid("pago_id"),
	diaOperativo: date("dia_operativo"),
	usuario: text(),
	medio: text(),
	referencia: text(),
	// TODO: failed to parse database type 'centimos_pos'
	montoCentimos: integer("monto_centimos"),
	desde: timestamp({ withTimezone: true, mode: 'string' }),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	numero: bigint({ mode: "number" }),
}).as(sql`SELECT pg.comercio_id, pg.id AS pago_id, t.dia_operativo, u.nombre AS usuario, pg.medio, pg.referencia, pg.monto_centimos, pg.resuelto_en AS desde, o.numero FROM pago pg JOIN orden o ON o.id = pg.orden_id JOIN turno t ON t.id = o.turno_id JOIN usuario u ON u.id = o.usuario_id WHERE pg.metodo = 'manual'::text AND pg.estado = 'exitoso'::text AND pg.conciliado_en IS NULL`);

export const vAlarmaSinPago = pgView("v_alarma_sin_pago", {	comercioId: uuid("comercio_id"),
	ventaId: uuid("venta_id"),
}).as(sql`SELECT comercio_id, id AS venta_id FROM v_venta_vigente v WHERE NOT (EXISTS ( SELECT 1 FROM pago pg WHERE pg.orden_id = v.orden_id AND pg.estado = 'exitoso'::text))`);

export const vAlarmaSinVenta = pgView("v_alarma_sin_venta", {	comercioId: uuid("comercio_id"),
	pagoId: uuid("pago_id"),
}).as(sql`SELECT pg.comercio_id, pg.id AS pago_id FROM pago pg JOIN orden o ON o.id = pg.orden_id WHERE pg.estado = 'exitoso'::text AND o.estado = 'pagada'::text AND NOT (EXISTS ( SELECT 1 FROM venta v WHERE v.orden_id = pg.orden_id))`);

export const vAlarmaCodigoMuerto = pgView("v_alarma_codigo_muerto", {	comercioId: uuid("comercio_id"),
	fichaId: uuid("ficha_id"),
	codigo: text(),
}).as(sql`SELECT comercio_id, id AS ficha_id, codigo FROM ficha f WHERE (estado = ANY (ARRAY['vendida'::text, 'activada'::text])) AND NOT en_router`);

export const vAlarmaFugaPool = pgView("v_alarma_fuga_pool", {	comercioId: uuid("comercio_id"),
	fichaId: uuid("ficha_id"),
	codigo: text(),
	// You can use { mode: "bigint" } if numbers are exceeding js number limitations
	uptimeSeg: bigint("uptime_seg", { mode: "number" }),
}).as(sql`SELECT f.comercio_id, f.id AS ficha_id, f.codigo, c.uptime_seg FROM ficha f JOIN consumo c ON c.ficha_id = f.id WHERE (f.estado = ANY (ARRAY['disponible'::text, 'reservada'::text, 'anulada'::text])) AND (c.uptime_seg > 0 OR c.bytes_in > 0)`);