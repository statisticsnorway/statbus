export default function handlerFor(setFieldValue) {
  return function onChange(event, props) {
    const propsValue = props.value === undefined ? null : props.value

    console.log('propsValue', propsValue)

    setFieldValue(props.name, propsValue)
  }
}
