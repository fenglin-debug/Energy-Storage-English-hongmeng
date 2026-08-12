import { relationalStore } from '@kit.ArkData';

export function columnIndex(result: relationalStore.ResultSet, name: string): number {
  return result.getColumnIndex(name);
}

export function stringValue(result: relationalStore.ResultSet, name: string): string {
  return result.getString(columnIndex(result, name));
}

export function nullableString(result: relationalStore.ResultSet, name: string): string | null {
  const index = columnIndex(result, name);
  return result.isColumnNull(index) ? null : result.getString(index);
}

export function integerValue(result: relationalStore.ResultSet, name: string): number {
  return result.getLong(columnIndex(result, name));
}

export function nullableInteger(result: relationalStore.ResultSet, name: string): number | null {
  const index = columnIndex(result, name);
  return result.isColumnNull(index) ? null : result.getLong(index);
}

export function numberValue(result: relationalStore.ResultSet, name: string): number {
  return result.getDouble(columnIndex(result, name));
}

export function nullableNumber(result: relationalStore.ResultSet, name: string): number | null {
  const index = columnIndex(result, name);
  return result.isColumnNull(index) ? null : result.getDouble(index);
}

export function booleanValue(result: relationalStore.ResultSet, name: string): boolean {
  return integerValue(result, name) !== 0;
}

export async function queryRows<T>(
  store: relationalStore.RdbStore,
  sql: string,
  mapper: (result: relationalStore.ResultSet) => T,
  bindArgs: relationalStore.ValueType[] = []
): Promise<T[]> {
  const result = await store.querySql(sql, bindArgs);
  const rows: T[] = [];
  try {
    if (result.goToFirstRow()) {
      do {
        rows.push(mapper(result));
      } while (result.goToNextRow());
    }
  } finally {
    result.close();
  }
  return rows;
}

export async function scalarString(
  store: relationalStore.RdbStore,
  sql: string,
  fallback: string = ''
): Promise<string> {
  const result = await store.querySql(sql);
  try {
    return result.goToFirstRow() ? result.getString(0) : fallback;
  } finally {
    result.close();
  }
}

export async function scalarNumber(
  store: relationalStore.RdbStore,
  sql: string,
  fallback: number = 0
): Promise<number> {
  const result = await store.querySql(sql);
  try {
    return result.goToFirstRow() ? result.getLong(0) : fallback;
  } finally {
    result.close();
  }
}
