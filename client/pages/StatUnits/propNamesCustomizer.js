export const customizePropNames = arr => arr.map(x => x.name === 'instSectorCode' || x.name === 'legalForm' ? { ...x, name: `${x.name}Id` } : x)
