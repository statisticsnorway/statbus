function escapeCSVStringValue(str: string) {
    let value = str.replace(/"/g, '""')
    return /[,\n"]/g.test(value) ? `"${value}"` : value
}

export function toCSV(entries: Object[]) {
    const header = Object.keys(entries[0]).join(',') + '\n'

    const body = entries
        .map(entry =>
            Object.values(entry).map(val => typeof val === 'string' ? escapeCSVStringValue(val) : val).join(',')
        ).join('\n')

    return {header, body}
}
