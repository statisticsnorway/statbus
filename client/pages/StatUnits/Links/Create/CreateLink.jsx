import React from 'react'
import { Button, Menu, Header, Form } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import UnitSearch, { defaultUnitSearchResult } from '../Components/UnitSearch'
import LinksGrid from '../Components/LinksGrid'

const { func, array, bool } = React.PropTypes

class CreateLink extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    createLink: func.isRequired,
    deleteLink: func.isRequired,
    links: array.isRequired,
    isLoading: bool.isRequired,
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
    }))
  }

  handleCreate = (e) => {
    e.preventDefault()
    this.props.createLink(this.state)
  }

  render() {
    const { localize, links, deleteLink, isLoading } = this.props
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
                {localize('ButtonCreate')}
              </Button>
            </Form.Field>
          </Form.Group>
        </Form>
        <LinksGrid localize={localize} data={links} deleteLink={deleteLink} />
      </div>
    )
  }
}

export default wrapper(CreateLink)
