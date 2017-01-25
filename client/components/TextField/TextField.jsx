import React from 'react'
import { Form, Message } from 'semantic-ui-react'
import { wrapper } from 'helpers/locale'

const TextField = ({ item, localize, errors }) => (
  <div>
    <Form.Input
      defaultValue={item.value}
      name={item.name}
      label={localize(item.localizeKey)}
      error={errors[item.name]}
    />
    {errors[item.name] &&
      <Message
        error
        header={localize(item.localizeKey)}
        content={errors[item.name][0]}
      />}
  </div>
)

const { func, shape, string, bool } = React.PropTypes

TextField.propTypes = {
  localize: func,
  item: shape({
    name: string,
    value: bool,
  }),
}

export default wrapper(TextField)
