import React from 'react'
import R from 'ramda'
import { Form, Message } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import getInnerErrors from 'helpers/schema'

const { func, node, object } = React.PropTypes

class FormWrapper extends React.Component {

  static propTypes = {
    children: node.isRequired,
    data: object, // eslint-disable-line react/forbid-prop-types
    schema: object, // eslint-disable-line react/forbid-prop-types
    localize: func.isRequired,
  }

  static defaultProps = {
    data: undefined,
    schema: undefined,
  }

  constructor(props, context) {
    super(props, context)
    this.state = {
      touched: false,
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
    this.setState(() => (this.state.touched
      ? { touched: false }
      : { errors }))
  }

  validate = (data, schema) => {
    schema
      .validate(data, { abortEarly: false })
      .then(() => this.setErrors({}))
      .catch(R.pipe(getInnerErrors, this.setErrors))
  }

  patchChildren = (children, errors, localize) => {
    const getErrorArr = (err, keyPrefix) => Array.isArray(err)
      ? err.map(er => <Message key={`${keyPrefix}${er}`} content={localize(er)} error />)
      : [<Message key={`${keyPrefix}${err}`} content={localize(err)} error />]

    return children.reduce(
      (acc, cur) => [
        ...acc,
        ...(errors[cur.props.name]
          ? [
            { ...cur, props: { ...cur.props, error: true } },
            ...getErrorArr(errors[cur.props.name], cur.props.name),
          ]
          : [cur]),
      ],
      [],
    )
  }

  render() {
    const {
      data, schema, // eslint-disable-line no-unused-vars
      dispatch, // eslint-disable-line no-unused-vars, react/prop-types
      children, localize,
      ...rest
    } = this.props
    const { errors } = this.state
    const isValid = R.isEmpty(errors)
    return (
      <Form {...rest} error={!isValid}>
        {isValid ? children : this.patchChildren(children, errors, localize)}
      </Form>
    )
  }
}

export default wrapper(FormWrapper)
