import React from 'react'
import { Form, Message } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import rqst from 'helpers/request'

class SelectField extends React.Component {
  constructor(props, context) {
    super(props, context)
    this.state = {
      lookup: [],
    }
  }

  componentDidMount() {
    const { item } = this.props
    rqst({
      url: `/api/lookup/${item.lookup}`,
      method: 'get',
      onSuccess: (lookup) => {
        this.setState({
          lookup,
        })
      },
      onFail: () => {},
      onError: () => {},
    })
  }

  render() {
    const { item, localize, errors } = this.props
    const options = this.state.lookup.map(x => ({ value: x.id, text: x.name }))
    const hasError = errors[item.name]
    return (
      <div>
        <Form.Select
          name={item.name}
          label={localize(item.localizeKey)}
          defaultValue={item.value}
          required={item.isRequired}
          options={options}
          multiple={this.props.multiselect}
          search
          error={hasError}
        />
        {errors[item.name] &&
        <Message
          error
          header={localize(item.localizeKey)}
          content={errors[item.name][0]}
        />}
      </div>

    )
  }
}

const { shape, string, number, func, bool } = React.PropTypes

SelectField.propTypes = {
  item: shape({
    name: string,
    value: number,
  }).isRequired,
  localize: func.isRequired,
  multiselect: bool,
}

export default wrapper(SelectField)
