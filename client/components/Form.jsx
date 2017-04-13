/* eslint-disable react/require-default-props */
import React from 'react'
import { shape } from 'prop-types'
import Formal from 'react-formal'
import { Form } from 'semantic-ui-react'
import { shouldUpdate } from 'recompose'
import { equals } from 'ramda'

const createInput = (Component, defaults) =>
  class Input extends React.Component {
    static propTypes = { meta: shape({}) }
    static defaultProps = defaults || {}
    render() {
      const { meta, ...props } = this.props
      return <Component {...props} />
    }
  }

const testProps = (curr, next) => !equals(curr, next)

const createField = (Component, defaults = {}) => {
  const type = createInput(Component, defaults)
  const field = props => <Formal.Field type={type} {...props} />
  return shouldUpdate(testProps)(field)
}

Formal.Select = createField(Form.Select, { options: [] })
Formal.Text = createField(Form.Input, { value: '' })
Formal.Button = Form.Button

export default Formal
