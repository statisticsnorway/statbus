import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import UnitSearch, { defaultUnitSearchResult } from '../Components/UnitSearch'

const { func, string, bool } = React.PropTypes

class LinkForm extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    onChange: func,
    onSubmit: func.isRequired,
    submitButtonText: string.isRequired,
    isLoading: bool.isRequired,
  }

  static defaultProps = {
    onChange: _ => _, //TODO: IMPLEMENT
  }

  state = {
    source1: defaultUnitSearchResult,
    source2: defaultUnitSearchResult,
    comment: '',
  }

  onFieldChanged = (e, { name, value }) => {
    this.setState(s => ({
      ...s,
      [name]: value,
    }), () => {
      // TODO: OnChange (IsChanged)
    })
  }

  handleCreate = (e) => {
    e.preventDefault()
    this.props.onSubmit(this.state)
  }

  render() {
    const { localize, isLoading, submitButtonText } = this.props
    const { source1, source2, comment } = this.state

    return (
      <div>
        <Form loading={isLoading}>
          <UnitSearch
            value={source1}
            name="source1"
            localize={localize}
            onChange={this.onFieldChanged}
          />
          <UnitSearch
            value={source2}
            name="source2"
            localize={localize}
            onChange={this.onFieldChanged}
            disabled={source1.code === ''}
          />
          <Form.Group>
            <Form.Input
              label={localize('Comment')}
              name="comment"
              value={comment}
              onChange={this.onFieldChanged}
              width={13}
              required
            />
            <Form.Field width={3}>
              <label>&nbsp;</label>
              <Button
                color="green"
                fluid
                type="submit"
                onClick={this.handleCreate}
                disabled={source1.code === '' || source2.code === '' || comment === ''}
              >
                {localize(submitButtonText)}
              </Button>
            </Form.Field>
          </Form.Group>
        </Form>
      </div>
    )
  }
}

export default LinkForm
