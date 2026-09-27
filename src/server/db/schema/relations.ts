import { relations } from "drizzle-orm/relations";
import { comercio, punto, contadorOrden, importacion, usuario, pago, orden, incidencia, turno, plan, movimientoCaja, cliente, lote, ficha, venta, anulacion, entrega, intentoVenta, stockCierre, consumo, auditoria } from "./schema";

export const puntoRelations = relations(punto, ({one, many}) => ({
	comercio: one(comercio, {
		fields: [punto.comercioId],
		references: [comercio.id]
	}),
	importacions: many(importacion),
	turnos: many(turno),
	lotes: many(lote),
}));

export const comercioRelations = relations(comercio, ({many}) => ({
	puntos: many(punto),
	contadorOrdens: many(contadorOrden),
	importacions: many(importacion),
	pagos: many(pago),
	incidencias: many(incidencia),
	plans: many(plan),
	usuarios: many(usuario),
	turnos: many(turno),
	movimientoCajas: many(movimientoCaja),
	clientes: many(cliente),
	lotes: many(lote),
	fichas: many(ficha),
	ordens: many(orden),
	ventas: many(venta),
	anulacions: many(anulacion),
	entregas: many(entrega),
	intentoVentas: many(intentoVenta),
	stockCierres: many(stockCierre),
	consumos: many(consumo),
	auditorias: many(auditoria),
}));

export const contadorOrdenRelations = relations(contadorOrden, ({one}) => ({
	comercio: one(comercio, {
		fields: [contadorOrden.comercioId],
		references: [comercio.id]
	}),
}));

export const importacionRelations = relations(importacion, ({one, many}) => ({
	comercio: one(comercio, {
		fields: [importacion.comercioId],
		references: [comercio.id]
	}),
	punto: one(punto, {
		fields: [importacion.comercioId],
		references: [punto.id]
	}),
	usuario: one(usuario, {
		fields: [importacion.comercioId],
		references: [usuario.id]
	}),
	lotes: many(lote),
}));

export const usuarioRelations = relations(usuario, ({one, many}) => ({
	importacions: many(importacion),
	pagos_comercioId: many(pago, {
		relationName: "pago_comercioId_usuario_id"
	}),
	pagos_comercioId: many(pago, {
		relationName: "pago_comercioId_usuario_id"
	}),
	incidencias_comercioId: many(incidencia, {
		relationName: "incidencia_comercioId_usuario_id"
	}),
	incidencias_comercioId: many(incidencia, {
		relationName: "incidencia_comercioId_usuario_id"
	}),
	comercio: one(comercio, {
		fields: [usuario.comercioId],
		references: [comercio.id]
	}),
	turnos: many(turno),
	movimientoCajas: many(movimientoCaja),
	ordens: many(orden),
	ventas: many(venta),
	anulacions: many(anulacion),
	entregas: many(entrega),
	intentoVentas: many(intentoVenta),
}));

export const pagoRelations = relations(pago, ({one}) => ({
	comercio: one(comercio, {
		fields: [pago.comercioId],
		references: [comercio.id]
	}),
	usuario_comercioId: one(usuario, {
		fields: [pago.comercioId],
		references: [usuario.id],
		relationName: "pago_comercioId_usuario_id"
	}),
	usuario_comercioId: one(usuario, {
		fields: [pago.comercioId],
		references: [usuario.id],
		relationName: "pago_comercioId_usuario_id"
	}),
	orden: one(orden, {
		fields: [pago.comercioId],
		references: [orden.id]
	}),
}));

export const ordenRelations = relations(orden, ({one, many}) => ({
	pagos: many(pago),
	incidencias: many(incidencia),
	cliente: one(cliente, {
		fields: [orden.comercioId],
		references: [cliente.id]
	}),
	comercio: one(comercio, {
		fields: [orden.comercioId],
		references: [comercio.id]
	}),
	ficha: one(ficha, {
		fields: [orden.comercioId],
		references: [ficha.id]
	}),
	plan: one(plan, {
		fields: [orden.comercioId],
		references: [plan.id]
	}),
	turno: one(turno, {
		fields: [orden.comercioId],
		references: [turno.id]
	}),
	usuario: one(usuario, {
		fields: [orden.comercioId],
		references: [usuario.id]
	}),
	ventas: many(venta),
}));

export const incidenciaRelations = relations(incidencia, ({one}) => ({
	comercio: one(comercio, {
		fields: [incidencia.comercioId],
		references: [comercio.id]
	}),
	orden: one(orden, {
		fields: [incidencia.comercioId],
		references: [orden.id]
	}),
	usuario_comercioId: one(usuario, {
		fields: [incidencia.comercioId],
		references: [usuario.id],
		relationName: "incidencia_comercioId_usuario_id"
	}),
	turno: one(turno, {
		fields: [incidencia.comercioId],
		references: [turno.id]
	}),
	usuario_comercioId: one(usuario, {
		fields: [incidencia.comercioId],
		references: [usuario.id],
		relationName: "incidencia_comercioId_usuario_id"
	}),
}));

export const turnoRelations = relations(turno, ({one, many}) => ({
	incidencias: many(incidencia),
	comercio: one(comercio, {
		fields: [turno.comercioId],
		references: [comercio.id]
	}),
	punto: one(punto, {
		fields: [turno.comercioId],
		references: [punto.id]
	}),
	usuario: one(usuario, {
		fields: [turno.comercioId],
		references: [usuario.id]
	}),
	movimientoCajas: many(movimientoCaja),
	ordens: many(orden),
	ventas: many(venta),
	anulacions: many(anulacion),
	intentoVentas: many(intentoVenta),
	stockCierres: many(stockCierre),
}));

export const planRelations = relations(plan, ({one, many}) => ({
	comercio: one(comercio, {
		fields: [plan.comercioId],
		references: [comercio.id]
	}),
	lotes: many(lote),
	ordens: many(orden),
	ventas: many(venta),
	intentoVentas: many(intentoVenta),
	stockCierres: many(stockCierre),
}));

export const movimientoCajaRelations = relations(movimientoCaja, ({one}) => ({
	comercio: one(comercio, {
		fields: [movimientoCaja.comercioId],
		references: [comercio.id]
	}),
	turno: one(turno, {
		fields: [movimientoCaja.comercioId],
		references: [turno.id]
	}),
	usuario: one(usuario, {
		fields: [movimientoCaja.comercioId],
		references: [usuario.id]
	}),
}));

export const clienteRelations = relations(cliente, ({one, many}) => ({
	comercio: one(comercio, {
		fields: [cliente.comercioId],
		references: [comercio.id]
	}),
	ordens: many(orden),
	ventas: many(venta),
}));

export const loteRelations = relations(lote, ({one, many}) => ({
	comercio: one(comercio, {
		fields: [lote.comercioId],
		references: [comercio.id]
	}),
	importacion: one(importacion, {
		fields: [lote.comercioId],
		references: [importacion.id]
	}),
	plan: one(plan, {
		fields: [lote.comercioId],
		references: [plan.id]
	}),
	punto: one(punto, {
		fields: [lote.comercioId],
		references: [punto.id]
	}),
	fichas_comercioId: many(ficha, {
		relationName: "ficha_comercioId_lote_id"
	}),
	fichas_puntoId: many(ficha, {
		relationName: "ficha_puntoId_lote_id"
	}),
}));

export const fichaRelations = relations(ficha, ({one, many}) => ({
	comercio: one(comercio, {
		fields: [ficha.comercioId],
		references: [comercio.id]
	}),
	lote_comercioId: one(lote, {
		fields: [ficha.comercioId],
		references: [lote.id],
		relationName: "ficha_comercioId_lote_id"
	}),
	lote_puntoId: one(lote, {
		fields: [ficha.puntoId],
		references: [lote.id],
		relationName: "ficha_puntoId_lote_id"
	}),
	ordens: many(orden),
	ventas: many(venta),
	consumos: many(consumo),
}));

export const ventaRelations = relations(venta, ({one, many}) => ({
	cliente: one(cliente, {
		fields: [venta.comercioId],
		references: [cliente.id]
	}),
	comercio: one(comercio, {
		fields: [venta.comercioId],
		references: [comercio.id]
	}),
	ficha: one(ficha, {
		fields: [venta.comercioId],
		references: [ficha.id]
	}),
	orden: one(orden, {
		fields: [venta.comercioId],
		references: [orden.id]
	}),
	plan: one(plan, {
		fields: [venta.comercioId],
		references: [plan.id]
	}),
	turno: one(turno, {
		fields: [venta.comercioId],
		references: [turno.id]
	}),
	usuario: one(usuario, {
		fields: [venta.comercioId],
		references: [usuario.id]
	}),
	anulacions: many(anulacion),
	entregas: many(entrega),
	intentoVentas: many(intentoVenta),
}));

export const anulacionRelations = relations(anulacion, ({one}) => ({
	comercio: one(comercio, {
		fields: [anulacion.comercioId],
		references: [comercio.id]
	}),
	turno: one(turno, {
		fields: [anulacion.comercioId],
		references: [turno.id]
	}),
	usuario: one(usuario, {
		fields: [anulacion.comercioId],
		references: [usuario.id]
	}),
	venta: one(venta, {
		fields: [anulacion.comercioId],
		references: [venta.id]
	}),
}));

export const entregaRelations = relations(entrega, ({one}) => ({
	comercio: one(comercio, {
		fields: [entrega.comercioId],
		references: [comercio.id]
	}),
	usuario: one(usuario, {
		fields: [entrega.comercioId],
		references: [usuario.id]
	}),
	venta: one(venta, {
		fields: [entrega.comercioId],
		references: [venta.id]
	}),
}));

export const intentoVentaRelations = relations(intentoVenta, ({one}) => ({
	comercio: one(comercio, {
		fields: [intentoVenta.comercioId],
		references: [comercio.id]
	}),
	plan: one(plan, {
		fields: [intentoVenta.comercioId],
		references: [plan.id]
	}),
	turno: one(turno, {
		fields: [intentoVenta.comercioId],
		references: [turno.id]
	}),
	usuario: one(usuario, {
		fields: [intentoVenta.comercioId],
		references: [usuario.id]
	}),
	venta: one(venta, {
		fields: [intentoVenta.comercioId],
		references: [venta.id]
	}),
}));

export const stockCierreRelations = relations(stockCierre, ({one}) => ({
	comercio: one(comercio, {
		fields: [stockCierre.comercioId],
		references: [comercio.id]
	}),
	plan: one(plan, {
		fields: [stockCierre.comercioId],
		references: [plan.id]
	}),
	turno: one(turno, {
		fields: [stockCierre.comercioId],
		references: [turno.id]
	}),
}));

export const consumoRelations = relations(consumo, ({one}) => ({
	comercio: one(comercio, {
		fields: [consumo.comercioId],
		references: [comercio.id]
	}),
	ficha: one(ficha, {
		fields: [consumo.fichaId],
		references: [ficha.id]
	}),
}));

export const auditoriaRelations = relations(auditoria, ({one}) => ({
	comercio: one(comercio, {
		fields: [auditoria.comercioId],
		references: [comercio.id]
	}),
}));