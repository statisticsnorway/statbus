import React from 'react'
import R from 'ramda'
import { Form, Message } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import getInnerErrors from 'helpers/schema'

const { func, node, object } = React.PropTypes

class FormWrapper extends React.Component {

  static propTypes = {
    onSubmit: func.isRequired,
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

  onSubmitStub = (e) => {
    e.preventDefault()
  }

  setErrors = (errors) => {
    this.setState(({ errors }))
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

    const patchInput = ({ props, ...restChild }) => [
      { ...restChild, props: { ...props, error: true } },
      ...getErrorArr(errors[props.name], props.name),
    ]
    
    return children.reduce(
      (acc, currChild) => [
        ...acc,
        ...(currChild.props.name && errors[currChild.props.name]
          ? patchInput(currChild)
          : [currChild.props.type === 'submit'
            ? { ...currChild, props: { ...currChild.props, disabled: true } }
            : currChild]),
      ],
      [],
    )
  }

  render() {
    const {
      data, schema, // eslint-disable-line no-unused-vars
      dispatch, // eslint-disable-line no-unused-vars, react/prop-types
      onSubmit, children, localize,
      ...rest
    } = this.props
    const { errors } = this.state
    const isValid = R.isEmpty(errors)
    return (
      <Form {...rest} error={!isValid} onSubmit={isValid ? onSubmit : this.onSubmitStub}>
        {isValid ? children : this.patchChildren(children, errors, localize)}
      </Form>
    )
  }
}

export default wrapper(FormWrapper)
