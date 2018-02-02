export default function handlerFor(setFieldValue) {
  return function onChange(event, props) {
    setFieldValue(props.name, props.value)
  }
}
