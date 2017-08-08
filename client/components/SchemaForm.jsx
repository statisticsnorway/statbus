/* eslint-disable react/require-default-props */
import React from 'react'
import { func, shape, string } from 'prop-types'
import { Formik } from 'formik'
import { Button, Form } from 'semantic-ui-react'

const getValue = props => props.radio ? props.value : props.checked || props.value

const createInput = (Component, defaults) =>
  class Input extends React.Component {

    static propTypes = {
      meta: shape({}),
      onChange: func.isRequired,
      type: string,
      htmlType: string,
    }

    static defaultProps = defaults || { }

    handleChange = (_, props) => {
      const { onChange } = this.props
      if (onChange) onChange(getValue(props), props)
    }

    render() {
      const { meta, onChange, htmlType, ...props } = this.props
      return <Component {...props} onChange={this.handleChange} type={htmlType} />
    }
  }

const createField = (Component, defaults = {}) => {
  const component = createInput(Component, defaults)
  // eslint-disable-next-line react/prop-types
  return props => <Formal.Field {...props} type={component} htmlType={props.type} />
}

const ErrorMessage = ({ at, ...props }) =>
  // eslint-disable-next-line react/no-unknown-property
  <Formal.Message {...props} for={at} errorClass="ui error message" />
ErrorMessage.propTypes = { at: string.isRequired }

const SchemaForm = ({ className, ...props }) =>
  <Formal {...props} className={`ui success error form ${className}`} />
SchemaForm.propTypes = {
  className: string,
}

// const selectKey = 'mySelect'
// Formal.addInputTypes(selectKey, createInput(Form.Select, { options: [] }))
// SchemaForm.Select = createField(selectKey)

// const inputKey = 'myInput'
// Formal.addInputTypes(inputKey, createInput(Form.Input))
// SchemaForm.Text = createField(inputKey)

SchemaForm.Checkbox = Form.Checkbox
SchemaForm.Button = Button
SchemaForm.Group = Form.Group
SchemaForm.Select = createField(Form.Select, { options: [] })
SchemaForm.Text = createField(Form.Input)
SchemaForm.Error = ErrorMessage
SchemaForm.Errors = props => <Formal.Summary errorClass="ui error message" {...props} />
SchemaForm.Trigger = Formal.Trigger

export default SchemaForm
