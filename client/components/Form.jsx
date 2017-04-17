/* eslint-disable react/require-default-props */
import React from 'react'
import { func, shape, string } from 'prop-types'
import Formal, { Message as FormalMessage } from 'react-formal'
import { Form } from 'semantic-ui-react'
import { shouldUpdate } from 'recompose'
import { equals, not, pipe } from 'ramda'

const createInput = (Component, defaults) =>
  class Input extends React.Component {

    static propTypes = {
      meta: shape({}),
      onChange: func.isRequired,
      type: string,
    }

    static defaultProps = defaults || { type: undefined }

    handleChange = (_, props) => {
      const value = props.radio
        ? props.value
        : props.checked || props.value
      this.props.onChange(value, props)
    }

    render() {
      // eslint-disable-next-line react/prop-types
      const { meta, onChange, value, ...props } = this.props
      if (onChange !== undefined) props.onChange = this.handleChange
      return <Component {...props} />
    }
  }

const testProps = pipe(equals, not)
const sCU = shouldUpdate(testProps)

const Message = props => <FormalMessage type={Form.Message} {...props} /> // TODO: seems like infinite loop here

const createField = (Component, defaults = {}) => {
  const type = createInput(Component, defaults)
  const Field = props => <Formal.Field type={type} {...props} />
  return sCU(Field)
}

Formal.Select = createField(Form.Select, { options: [] })
Formal.Text = createField(Form.Input, { value: '' })
Formal.Button = Form.Button
Formal.Message = sCU(Message)

export default Formal
