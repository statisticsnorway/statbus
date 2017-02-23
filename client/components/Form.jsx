import React from 'react'
import R from 'ramda'
import { Form } from 'semantic-ui-react'

const { object } = React.PropTypes

class Wrapper extends React.Component {

  static propTypes = {
    data: object, // eslint-disable-line react/forbid-prop-types
    schema: object, // eslint-disable-line react/forbid-prop-types
  }

  static defaultProps = {
    data: undefined,
    schema: undefined,
  }

  constructor(props, context) {
    super(props, context)
    this.state = {
      data: props.data ? undefined : {},
      errors: props.schema ? {} : undefined,
    }
  }

  componentWillReceiveProps(newProps) {
    const shouldValidate = !R.equals(this.props, newProps)
      && newProps.data
      && newProps.schema
    if (shouldValidate) this.validate(newProps.data, newProps.schema)
  }

  setErrors = (errors) => {
    this.setState(() => ({ errors }))
  }

  validate = (data, schema) => {
    const parseErrors = err => err.inner.reduce(
      (prev, cur) => ({ ...prev, [cur.path]: cur.errors }),
      {},
    )
    schema
      .validate(data, { abortEarly: false })
      .then(this.setErrors)
      .catch(R.pipe(parseErrors, this.setErrors))
  }

  render() {
    // eslint-disable-next-line no-unused-vars
    const { data, schema, ...rest } = this.props
    const isValid = R.isEmpty(this.state.errors)
    return <Form {...rest} />
  }
}

export default Wrapper
