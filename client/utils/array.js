let uid = 0
const getIncrement = () => uid++

export const setUids = (arr, propName = 'uid') => arr.map(x => ({ [propName]: getIncrement(), ...x }))
