import React from 'react'
import { Button, Form } from 'semantic-ui-react'
import { func, string, bool, shape, object, number } from 'prop-types'

import UnitSearch, { defaultUnitSearchResult } from './UnitSearch.jsx'

class LinkForm extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    onChange: func.isRequired,
    onSubmit: func.isRequired,
    submitButtonText: string.isRequired,
    submitButtonColor: string.isRequired,
    isLoading: bool.isRequired,
    data: shape({
      source1: object,
      source2: object,
      comment: string,
      statUnitType: number,
      isDeleted: bool,
    }),
  }

  static defaultProps = {
    data: {
      source1: defaultUnitSearchResult,
      source2: defaultUnitSearchResult,
      comment: '',
      statUnitType: undefined,
      isDeleted: false,
    },
  }

  onFieldChanged = (e, { name, value }) => {
    const { onChange, data } = this.props
    onChange({
      ...data,
      [name]: value,
    })
  }

  handleCreate = (e) => {
    e.preventDefault()
    this.props.onSubmit(this.props.data)
  }

  render() {
    const {
      localize,
      isLoading,
      data: { source1, source2, comment, statUnitType, isDeleted },
      submitButtonText,
      submitButtonColor,
    } = this.props
    return (
      <div>
        <Form loading={isLoading}>
          <UnitSearch
            value={source1}
            type={statUnitType}
            isDeleted={isDeleted}
            name="source1"
            localize={localize}
            onChange={this.onFieldChanged}
          />
          <UnitSearch
            value={{ ...source2, regId: source1.id }}
            type={statUnitType}
            isDeleted={isDeleted}
            name="source2"
            localize={localize}
            onChange={this.onFieldChanged}
            disabled={!source1.id}
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
              <label htmlFor="submitBtn">&nbsp;</label>
              <Button
                id="submitBtn"
                color={submitButtonColor}
                fluid
                type="submit"
                onClick={this.handleCreate}
                disabled={!(source1.id && source2.id && comment)}
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
