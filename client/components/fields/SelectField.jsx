import React from 'react'
import { Form, Message } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import { internalRequest } from 'helpers/request'

const { arrayOf, string, number, oneOfType, func, bool } = React.PropTypes

class SelectField extends React.Component {

  static propTypes = {
    lookup: number,
    name: string.isRequired,
    value: oneOfType([arrayOf(number), number]),
    labelKey: string.isRequired,
    onChange: func.isRequired,
    localize: func.isRequired,
    multiselect: bool,
    required: bool,
    errors: arrayOf(string).isRequired,
  }

  static defaultProps = {
    value: '',
    lookup: '',
    multiselect: false,
    required: false,
  }

  state = {
    lookup: [],
  }

  componentDidMount() {
    internalRequest({
      url: `/api/lookup/${this.props.lookup}`,
      method: 'get',
      onSuccess: (lookup) => { this.setState({ lookup }) },
    })
  }

  render() {
    const { name, value, required, labelKey, onChange, localize, errors } = this.props
    const options = this.state.lookup.map(x => ({ value: x.id, text: x.name }))
    return (
      <div className="field">
        <Form.Select
          name={name}
          onChange={onChange}
          value={value || ''}
          label={localize(labelKey)}
          required={required}
          options={options}
          multiple={this.props.multiselect}
          search
          error={errors.length !== 0}
        />
      </div>
    )
  }
}

export default wrapper(SelectField)
