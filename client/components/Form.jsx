/* eslint-disable react/require-default-props */
import React from 'react'
import { func, shape } from 'prop-types'
import Formal from 'react-formal'
import { Form } from 'semantic-ui-react'
import { shouldUpdate } from 'recompose'
import { equals, not, pipe } from 'ramda'

const createInput = (Component, defaults) =>
  class Input extends React.Component {

    static propTypes = {
      meta: shape({}),
      onChange: func.isRequired,
    }

    static defaultProps = defaults || {}

    handleChange = (_, { value, checked, selected }) =>
      this.props.onChange(value || checked || selected)

    render() {
      // eslint-disable-next-line react/prop-types
      const { meta, onChange, value, ...props } = this.props
      return <Component {...props} onChange={this.handleChange} value={value || ''} />
    }
  }

const testProps = pipe(equals, not)

const createField = (Component, defaults = {}) => {
  const type = createInput(Component, defaults)
  const field = props => <Formal.Field type={type} {...props} />
  return shouldUpdate(testProps)(field)
}

Formal.Select = createField(Form.Select, { options: [] })
Formal.Text = createField(Form.Input, { value: '' })
Formal.Button = Form.Button

export default Formal
