export default (status) => {
  const result = {
    info: false,
    negative: false,
    positive: false,
  }
  switch (status) {
    case -1:
      result.negative = true
      break
    case 2:
      result.positive = true
      break
    case 1:
      result.info = true
      break
    default:
      break
  }
  return result
}
