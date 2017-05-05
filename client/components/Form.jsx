/* eslint-disable react/require-default-props */
import React from 'react'
import { func, shape, string } from 'prop-types'
import Formal from 'react-formal'
import { Form } from 'semantic-ui-react'

const getValue = props => props.radio ? props.value : props.checked || props.value

const createInput = (Component, defaults) =>
  class Input extends React.Component {

    static propTypes = {
      meta: shape({}),
      onChange: func.isRequired,
      type: string,
    }

    static defaultProps = defaults || { }

    handleChange = (_, props) => {
      const { onChange } = this.props
      if (onChange) onChange(getValue(props), props)
    }

    render() {
      // eslint-disable-next-line react/prop-types
      const { meta, onChange, ...props } = this.props
      return <Component {...props} onChange={this.handleChange} />
    }
  }

const createField = (Component, defaults = {}) => {
  const type = createInput(Component, defaults)
  return props => <Formal.Field type={type} {...props} />
}

const ErrorMessage = ({ at, ...props }) =>
  // eslint-disable-next-line react/no-unknown-property
  <Formal.Message {...props} for={at} errorClass="ui error message" />
ErrorMessage.propTypes = { at: string.isRequired }

const CustomForm = ({ className, ...props }) => <Formal {...props} className={`ui success error form ${className}`} />
CustomForm.propTypes = {
  className: string,
}

CustomForm.Button = Form.Button
CustomForm.Group = Form.Group
CustomForm.Select = createField(Form.Select, { options: [] })
CustomForm.Text = createField(Form.Input)
CustomForm.Error = ErrorMessage
CustomForm.Errors = props => <Formal.Summary errorClass="ui error message" {...props} />

export default CustomForm
